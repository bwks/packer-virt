# packer-virt

Packer templates for building QCOW2 base images from Ubuntu cloud images.
Images are pre-configured to host KVM/QEMU/libvirt virtual machines and
Docker containers, and are fully customisable via cloud-init at boot time.

## Images

| Template | Base | Virtual size | Includes |
|----------|------|-------------|---------|
| `ubuntu-2404.pkr.hcl` | Ubuntu 24.04 (Noble) | 10 GiB | KVM/libvirt, Docker CE |

## Requirements

- **Packer** >= 1.10.0
- **QEMU** with KVM acceleration (`/dev/kvm` must exist)
- Packer QEMU plugin — installed automatically on first run, or manually:
  ```bash
  packer plugins install github.com/hashicorp/qemu
  ```

## Building

```bash
packer build ubuntu-2404.pkr.hcl
```

The Ubuntu cloud image (~600 MB) is downloaded and cached on the first run.
The finished image is written to `output/ubuntu-2404-base.qcow2`.

### Variables

Override defaults with `-var`:

```bash
packer build \
  -var="output_dir=/srv/images" \
  -var="disk_size=20480" \
  -var="cpus=4" \
  -var="memory=4096" \
  ubuntu-2404.pkr.hcl
```

| Variable | Default | Description |
|----------|---------|-------------|
| `output_dir` | `output` | Directory for the finished image |
| `disk_size` | `10240` | Disk size in MB |
| `cpus` | `2` | vCPUs for the build VM |
| `memory` | `2048` | RAM in MB for the build VM |

## What's installed

### KVM / QEMU / libvirt
- `qemu-kvm`
- `libvirt-daemon-system`
- `libvirt-clients`
- `virtinst` (`virt-install`)
- `bridge-utils`
- `cpu-checker` (`kvm-ok`)

### Docker CE (official Docker repo)
- `docker-ce`
- `docker-ce-cli`
- `containerd.io`
- `docker-buildx-plugin`
- `docker-compose-plugin`

The `ubuntu` user is added to the `docker`, `libvirt`, and `kvm` groups.

## Using the image

The image ships with no machine-id and a wiped cloud-init state, making
it suitable as a golden template. Every VM booted from it is customised
via a standard cloud-init config (user-data / meta-data).

### Boot with virsh / virt-install

```bash
# Create a copy-on-write overlay so the base image stays unmodified
qemu-img create -f qcow2 -b ubuntu-2404-base.qcow2 -F qcow2 my-vm.qcow2 20G

virt-install \
  --name my-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk path=my-vm.qcow2,format=qcow2 \
  --cloud-init user-data=my-user-data.yaml \
  --os-variant ubuntu24.04 \
  --import \
  --noautoconsole
```

### Minimal cloud-init example

```yaml
#cloud-config
users:
  - name: alice
    groups: [sudo, docker, libvirt]
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... alice@example.com
    sudo: ALL=(ALL) NOPASSWD:ALL
```

## Testing

The test script boots a throw-away overlay VM and verifies that all
expected packages and services are present:

```bash
bash test/test-vm.sh
```

All 15 checks must pass before an image is considered good.

## Project layout

```
ubuntu-2404.pkr.hcl   # Packer template
cloud-init/
  user-data            # Build-time cloud-init seed (wiped before output)
  meta-data            # NoCloud instance metadata
scripts/
  install.sh           # Package installation provisioner
test/
  test-vm.sh           # Automated VM boot + package verification
output/                # Build artefacts — gitignored
```
