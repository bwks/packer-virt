packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "output_dir" {
  description = "Directory where the output image will be written"
  default     = "output"
}

variable "disk_size" {
  description = "Disk size in MB"
  default     = 10240
}

variable "cpus" {
  description = "Number of vCPUs for the build VM"
  default     = 2
}

variable "memory" {
  description = "Memory in MB for the build VM"
  default     = 2048
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  image_name = "ubuntu-2404-base"
  iso_url    = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "qemu" "ubuntu-2404" {
  # Source cloud image
  iso_url      = local.iso_url
  iso_checksum = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"

  # Treat the source as a disk image rather than an install ISO
  disk_image = true

  # Output
  output_directory = var.output_dir
  vm_name          = "${local.image_name}.qcow2"
  format           = "qcow2"
  disk_size        = var.disk_size

  # Machine
  accelerator  = "kvm"
  machine_type = "q35"
  cpus         = var.cpus
  memory       = var.memory

  # Devices
  net_device      = "virtio-net"
  disk_interface  = "virtio"

  # Cloud-init NoCloud seed — label must be "cidata"
  cd_files = [
    "./cloud-init/user-data",
    "./cloud-init/meta-data",
  ]
  cd_label = "cidata"

  # SSH communicator
  ssh_username = "ubuntu"
  ssh_password = "ubuntu"
  ssh_timeout  = "20m"

  boot_wait = "10s"
  headless  = true

  shutdown_command = "sudo shutdown -P now"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  name    = "ubuntu-2404-base"
  sources = ["source.qemu.ubuntu-2404"]

  # Wait for cloud-init to finish before touching the system
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  # Install packages
  provisioner "shell" {
    script = "scripts/install.sh"
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
  }

  # Reset cloud-init state so the output image is a clean template,
  # and fstrim the filesystem so freed blocks are reclaimed by the host.
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo fstrim -av",
      "sudo sync",
    ]
  }

  # Re-convert the image so only allocated (non-zero) blocks are written,
  # effectively sparsifying without requiring libguestfs/supermin.
  post-processor "shell-local" {
    inline = [
      "echo '==> Sparsifying output image via qemu-img convert...'",
      "mv ${var.output_dir}/${local.image_name}.qcow2 ${var.output_dir}/${local.image_name}.tmp.qcow2",
      "qemu-img convert -O qcow2 -S 4k ${var.output_dir}/${local.image_name}.tmp.qcow2 ${var.output_dir}/${local.image_name}.qcow2",
      "rm ${var.output_dir}/${local.image_name}.tmp.qcow2",
      "echo '==> Done. Final image size:'",
      "qemu-img info ${var.output_dir}/${local.image_name}.qcow2",
    ]
  }
}
