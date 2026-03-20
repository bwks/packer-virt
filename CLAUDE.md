# CLAUDE.md — packer-virt

This repo builds QCOW2 base images for KVM/QEMU/libvirt using Packer.
Images are sourced from Ubuntu cloud images and configured for hosting
both VMs and Docker containers.

## Repo layout

```
ubuntu-2404.pkr.hcl   # Packer template
cloud-init/
  user-data            # Build-time cloud-init (wiped before output)
  meta-data            # NoCloud seed metadata
scripts/
  install.sh           # Package installation provisioner
test/
  test-vm.sh           # Boots an overlay VM and runs checks over SSH
output/                # Build artefacts (gitignored)
```

## How to build

```bash
packer build ubuntu-2404.pkr.hcl
```

The source image (~600 MB) is cached in `~/.cache/packer/` after the
first download. Subsequent builds reuse the cache.

Output: `output/ubuntu-2404-base.qcow2`
- Virtual size: 10 GiB
- Actual size: ~4 GiB (sparsified post-build)

## How to test

```bash
bash test/test-vm.sh
```

Boots a throw-away QCOW2 overlay of the base image (no modifications
to the base), injects a temporary SSH key via cloud-init, SSHes in,
runs 15 checks, then tears down. Requires no extra tools beyond what
is already installed.

## What each image contains

- **KVM/QEMU/libvirt**: `qemu-kvm`, `libvirt-daemon-system`,
  `libvirt-clients`, `virtinst`, `bridge-utils`, `cpu-checker`
- **Docker CE** (official repo): `docker-ce`, `docker-ce-cli`,
  `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- `ubuntu` user in `docker`, `libvirt`, `kvm` groups
- `machine-id` cleared — each booted instance generates a fresh one
- `cloud-init` state wiped — images are fully configurable by end-users

## Environment notes

- Host: x86_64 Linux with KVM acceleration (`/dev/kvm` present)
- Packer: v1.15.0, plugin `github.com/hashicorp/qemu` v1.1.4
- `virt-sparsify --in-place` does NOT work in this environment
  (supermin/libguestfs fails). Sparsification is done instead with
  `fstrim` inside the guest + `qemu-img convert -S 4k` as a
  shell-local post-processor.
- `sshpass` is not installed. Tests use temporary ed25519 key pairs
  injected via cloud-init user-data.
- GitHub remote: `https://github.com/bwks/packer-virt.git`
  Push requires using the GH_TOKEN: `gh auth token`

## Adding a new image

1. Copy `ubuntu-2404.pkr.hcl` and update `locals` (image name, ISO URL).
2. Add a matching provisioner script under `scripts/`.
3. Add a test in `test/` following the same pattern as `test-vm.sh`.
4. Validate with `packer validate <template>.pkr.hcl` before building.
