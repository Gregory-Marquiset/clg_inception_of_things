#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "a lancer avec sudo" >&2
  exit 1
}

TARGET_USER="${SUDO_USER:-root}"
K3D_VERSION=v5.9.0
K8S_MINOR=v1.34

install -m 0755 -d /etc/apt/keyrings

if ! command -v docker >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi

usermod -aG docker "$TARGET_USER"

if ! command -v kubectl >/dev/null; then
  curl -fsSL \
    "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
  apt-get update -qq
  apt-get install -y -qq kubectl
fi

if ! command -v k3d >/dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
    | TAG="$K3D_VERSION" bash
fi

docker --version
kubectl version --client
k3d version
