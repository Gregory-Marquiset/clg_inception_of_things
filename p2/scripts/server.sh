#!/bin/sh
set -eu

NODE_IP="$1"

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
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${NODE_IP} \
  --advertise-address=${NODE_IP} \
  --flannel-iface=${IFACE} \
  --tls-san=${NODE_IP} \
  --write-kubeconfig-mode=644" sh -

echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' \
  > /etc/profile.d/k3s.sh
chmod 644 /etc/profile.d/k3s.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 60); do
  kubectl get nodes --no-headers 2>/dev/null \
    | grep -q . && break
  sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=120s
for i in $(seq 1 60); do
  kubectl -n kube-system get deploy traefik \
    >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n kube-system rollout status \
  deployment/traefik --timeout=180s
kubectl apply -f /tmp/confs/

kubectl rollout status deployment/app-one   --timeout=120s
kubectl rollout status deployment/app-two   --timeout=120s
kubectl rollout status deployment/app-three --timeout=120s

kubectl get all
kubectl get ingress
