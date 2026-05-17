#!/bin/bash
set -e

# Detect distro
DISTRO=$(. /etc/os-release && echo "$ID")
case "$DISTRO" in
    ubuntu|debian) ;;
    *) echo "Error: Unsupported distro '$DISTRO'. This script supports Ubuntu and Debian only." && exit 1 ;;
esac

echo "=== Detected distro: $DISTRO ==="

echo "=== Updating package index ==="
sudo apt-get update -y

echo "=== Installing prerequisites ==="
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "=== Adding Docker's official GPG key ==="
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$DISTRO/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "=== Setting up Docker repository for $DISTRO ==="
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "=== Updating package index (with Docker repo) ==="
sudo apt-get update -y

echo "=== Installing Docker Engine, CLI, containerd, and plugins ==="
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Enabling and starting Docker service ==="
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Adding current user ($USER) to docker group ==="
sudo usermod -aG docker "$USER"

echo "=== Installation complete ==="
echo "You may need to log out and log back in for group changes to take effect."
docker --version
