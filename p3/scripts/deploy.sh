#!/bin/sh
set -eu

CLUSTER=iot
ARGOCD_VERSION=v3.6.3
CONFS="$(cd "$(dirname "$0")/../confs" && pwd)"

k3d cluster list 2>/dev/null | grep -q "^${CLUSTER} " \
  || k3d cluster create "$CLUSTER" \
       --servers 1 --agents 0 \
       -p "8888:30888@server:0" \
       -p "8080:30080@server:0"

kubectl config use-context "k3d-${CLUSTER}"

for ns in argocd dev; do
  kubectl create namespace "$ns" \
    --dry-run=client -o yaml | kubectl apply -f -
done

kubectl apply -n argocd --server-side --force-conflicts -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl -n argocd rollout status \
  deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status \
  deployment/argocd-repo-server --timeout=300s

kubectl apply -f "${CONFS}/argocd-nodeport.yaml"
kubectl apply -f "${CONFS}/application.yaml"

for i in $(seq 1 60); do
  kubectl -n dev get deploy playground >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n dev rollout status \
  deployment/playground --timeout=180s

echo
echo "interface Argo CD : https://localhost:8080"
echo "utilisateur       : admin"
printf "mot de passe      : "
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
echo "application       : curl http://localhost:8888/"
