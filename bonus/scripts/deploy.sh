#!/bin/sh
set -eu

CLUSTER=iot
ARGOCD_VERSION=v3.6.3
GITLAB_HOST=gitlab.gitlab.svc.cluster.local
ROOT_PASSWORD=IoT42-gitlab-root
CONFS="$(cd "$(dirname "$0")/../confs" && pwd)"

echo "== 1/7 cluster k3d"
k3d cluster list 2>/dev/null | grep -q "^${CLUSTER} " \
  || k3d cluster create "$CLUSTER" \
       --servers 1 --agents 0 \
       -p "8888:30888@server:0" \
       -p "8080:30080@server:0" \
       -p "80:30081@server:0"
kubectl config use-context "k3d-${CLUSTER}" >/dev/null
echo "== 2/7 namespaces"
for ns in argocd dev gitlab; do
  kubectl create namespace "$ns" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

echo "== 3/7 resolution du nom de GitLab sur l hote"
grep -q "$GITLAB_HOST" /etc/hosts || \
  echo "127.0.0.1 $GITLAB_HOST" | sudo tee -a /etc/hosts >/dev/null
echo "== 4/7 GitLab (comptez 5 a 8 minutes)"
kubectl apply -f "${CONFS}/gitlab.yaml" >/dev/null
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" \
    "http://${GITLAB_HOST}/" 2>/dev/null || echo 000)
  case "$code" in 200|302) break;; esac
  sleep 10
done
POD=$(kubectl -n gitlab get pod -l app=gitlab \
  -o jsonpath='{.items[0].metadata.name}')

echo "== 5/7 migration et amorcage (filet de securite)"
kubectl -n gitlab exec "$POD" -- gitlab-rake db:migrate   >/dev/null 2>&1 || true
kubectl -n gitlab exec "$POD" -- gitlab-rake db:seed_fu   >/dev/null 2>&1 || true
echo "== 6/7 depot public et manifeste de l application"
TOKEN=$(kubectl -n gitlab exec "$POD" -- gitlab-rails runner "
u = User.find_by_username(%q{root})
u.password = %q{${ROOT_PASSWORD}}
u.password_confirmation = %q{${ROOT_PASSWORD}}
u.skip_confirmation!
u.save!(validate: false)
p = Project.find_by_full_path(%q{root/iot}) ||
    Projects::CreateService.new(u, name: %q{iot}, path: %q{iot},
      namespace_id: u.namespace.id, visibility_level: 20,
      initialize_with_readme: true).execute
t = u.personal_access_tokens.active.find_by(name: %q{deploy}) ||
    u.personal_access_tokens.create!(
      scopes: [%q{api}, %q{write_repository}],
      name: %q{deploy}, expires_at: 300.days.from_now)
puts t.token
" 2>/dev/null | tail -1)
WORK=$(mktemp -d)
git clone -q "http://oauth2:${TOKEN}@${GITLAB_HOST}/root/iot.git" "$WORK"
cp "${CONFS}/deployment.yaml" "$WORK/deployment.yaml"
cd "$WORK"
if [ -n "$(git status --porcelain)" ]; then
  git -c user.email=iot@42.fr -c user.name=iot add deployment.yaml
  git -c user.email=iot@42.fr -c user.name=iot commit \
      -qm "manifeste de l application"
  git push -q origin HEAD:main
fi
cd - >/dev/null
rm -rf "$WORK"
echo "== 7/7 Argo CD"
kubectl apply -n argocd --server-side --force-conflicts -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl apply -f "${CONFS}/argocd-nodeport.yaml" >/dev/null
kubectl apply -f "${CONFS}/application.yaml" >/dev/null
for i in $(seq 1 40); do
  kubectl -n dev get deploy playground >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n dev rollout status deployment/playground --timeout=180s
echo
echo "GitLab    http://${GITLAB_HOST}      root / ${ROOT_PASSWORD}"
echo "Argo CD   https://localhost:8080     admin / $(kubectl -n argocd \
  get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"
echo "App       curl http://localhost:8888/"
