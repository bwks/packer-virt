#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-vm.sh — Boot the built image in a throw-away VM and verify packages
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BASE_IMAGE="${REPO_DIR}/output/ubuntu-2404-base.qcow2"

TEST_IMAGE="/tmp/test-ubuntu-2404.qcow2"
SEED_ISO="/tmp/test-seed.iso"
CLOUD_INIT_DIR="/tmp/test-cloudinit"
SSH_KEY="/tmp/test-ubuntu-key"
SSH_PORT=2299
SSH_USER="ubuntu"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "==> Cleaning up..."
  if [[ -n "${VM_PID:-}" ]] && kill -0 "$VM_PID" 2>/dev/null; then
    kill "$VM_PID" 2>/dev/null || true
    wait "$VM_PID" 2>/dev/null || true
  fi
  rm -f "$TEST_IMAGE" "$SEED_ISO" "$SSH_KEY" "${SSH_KEY}.pub"
  rm -rf "$CLOUD_INIT_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
check() {
  if [[ ! -f "$BASE_IMAGE" ]]; then
    echo "ERROR: Base image not found: $BASE_IMAGE"
    echo "       Run 'packer build ubuntu-2404.pkr.hcl' first."
    exit 1
  fi
  for cmd in qemu-system-x86_64 qemu-img cloud-localds ssh; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "ERROR: required tool not found: $cmd"
      exit 1
    fi
  done
}

# ---------------------------------------------------------------------------
run_test() {
  local desc="$1"
  local cmd="$2"
  printf "  %-55s" "TEST: $desc"
  if ssh -i "$SSH_KEY" \
         -o StrictHostKeyChecking=no \
         -o BatchMode=yes \
         -o ConnectTimeout=10 \
         -p "$SSH_PORT" \
         "${SSH_USER}@localhost" \
         "$cmd" &>/dev/null; then
    echo "PASS"
    ((PASS++)) || true
  else
    echo "FAIL"
    ((FAIL++)) || true
  fi
}

# ---------------------------------------------------------------------------
echo "==> Checking prerequisites..."
check

echo "==> Generating temporary SSH key pair..."
ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "packer-test" -q

echo "==> Creating throw-away overlay image..."
qemu-img create -f qcow2 -b "$(realpath "$BASE_IMAGE")" -F qcow2 "$TEST_IMAGE" >/dev/null

echo "==> Creating cloud-init seed..."
mkdir -p "$CLOUD_INIT_DIR"
PUB_KEY="$(cat "${SSH_KEY}.pub")"

cat > "${CLOUD_INIT_DIR}/user-data" <<EOF
#cloud-config
ssh_authorized_keys:
  - ${PUB_KEY}
EOF

cat > "${CLOUD_INIT_DIR}/meta-data" <<EOF
instance-id: test-$(date +%s)
local-hostname: test-vm
EOF

cloud-localds "$SEED_ISO" "${CLOUD_INIT_DIR}/user-data" "${CLOUD_INIT_DIR}/meta-data"

echo "==> Booting test VM (port-forwarded SSH on localhost:${SSH_PORT})..."
qemu-system-x86_64 \
  -name "test-ubuntu-2404" \
  -machine q35,accel=kvm \
  -cpu host \
  -smp 2 \
  -m 2048 \
  -drive "file=${TEST_IMAGE},if=virtio,format=qcow2" \
  -drive "file=${SEED_ISO},if=virtio,format=raw" \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
  -device virtio-net-pci,netdev=net0 \
  -nographic \
  -serial none \
  -monitor none \
  &>/tmp/test-vm-console.log &
VM_PID=$!

echo "==> Waiting for SSH to become available (up to 120s)..."
for i in $(seq 1 24); do
  if ssh -i "$SSH_KEY" \
         -o StrictHostKeyChecking=no \
         -o BatchMode=yes \
         -o ConnectTimeout=5 \
         -p "$SSH_PORT" \
         "${SSH_USER}@localhost" \
         "echo connected" &>/dev/null; then
    echo "    SSH ready after $((i * 5))s."
    break
  fi
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    echo "ERROR: VM process exited unexpectedly. Console log:"
    cat /tmp/test-vm-console.log || true
    exit 1
  fi
  echo "    Still waiting... ($((i * 5))s / 120s)"
  sleep 5
done

echo ""
echo "==> Running tests..."
echo "    -------------------------------------------------------"

# KVM / QEMU
run_test "qemu-kvm binary exists"          "test -f /usr/bin/qemu-system-x86_64"
run_test "kvm module loaded"               "lsmod | grep -q kvm"
run_test "libvirtd service enabled"        "systemctl is-enabled libvirtd"
run_test "libvirtd service active"         "sudo systemctl is-active libvirtd"
run_test "virsh available"                 "which virsh"
run_test "ubuntu in libvirt group"         "id | grep -q libvirt"
run_test "ubuntu in kvm group"             "id | grep -q kvm"

# Docker
run_test "docker binary exists"            "which docker"
run_test "docker service enabled"          "systemctl is-enabled docker"
run_test "docker service active"           "sudo systemctl is-active docker"
run_test "containerd service active"       "sudo systemctl is-active containerd"
run_test "docker compose plugin present"   "docker compose version"
run_test "ubuntu in docker group"          "id | grep -q docker"

# cloud-init
run_test "cloud-init present"              "which cloud-init"
run_test "machine-id was regenerated fresh" "test -s /etc/machine-id"

echo "    -------------------------------------------------------"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "==> All $PASS tests passed."
  EXIT_CODE=0
else
  echo "==> $PASS passed, $FAIL failed."
  EXIT_CODE=1
fi

echo "==> Shutting down test VM..."
ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -p "$SSH_PORT" \
    "${SSH_USER}@localhost" \
    "sudo shutdown -P now" &>/dev/null || true

wait "$VM_PID" 2>/dev/null || true
unset VM_PID

exit $EXIT_CODE
