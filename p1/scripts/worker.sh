#!/bin/sh
set -eu

NODE_IP="$1"
K3S_TOKEN="$2"
K3S_URL="$3"

command -v curl >/dev/null || {
  apt-get update -qq
  apt-get install -y -qq curl
}

IFACE=$(ip -o -4 addr show \
  | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')

[ -n "$IFACE" ] || {
  echo "aucune interface ne porte $NODE_IP" >&2
  exit 1
}

export K3S_TOKEN K3S_URL
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --node-ip=${NODE_IP} \
  --flannel-iface=${IFACE}" sh -
