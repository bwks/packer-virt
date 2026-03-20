#!/usr/bin/env bash
set -euxo pipefail

# ---------------------------------------------------------------------------
# System update
# ---------------------------------------------------------------------------
sudo apt-get update
sudo apt-get upgrade -y

# ---------------------------------------------------------------------------
# KVM / QEMU / libvirt
# ---------------------------------------------------------------------------
sudo apt-get install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  bridge-utils \
  cpu-checker

sudo systemctl enable libvirtd

# Add ubuntu user to the virtualisation groups
sudo usermod -aG libvirt ubuntu
sudo usermod -aG kvm ubuntu

# ---------------------------------------------------------------------------
# Docker CE (official repo)
# ---------------------------------------------------------------------------
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable docker
sudo systemctl enable containerd

sudo usermod -aG docker ubuntu

# ---------------------------------------------------------------------------
# Clean up to keep the image small
# ---------------------------------------------------------------------------
sudo apt-get autoremove -y
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
