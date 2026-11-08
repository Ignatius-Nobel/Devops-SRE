#!/usr/bin/env bash
# One-shot local environment bootstrap. Requires: docker, k3d, kubectl, helm.
# Usage:  REPO_URL=https://github.com/<you>/<repo>.git SLACK_WEBHOOK_URL=... ./scripts/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${REPO_URL:?set REPO_URL, e.g. https://github.com/you/sre-assessment.git}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/REPLACE/ME/PLEASE}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 18)}"
APP_API_KEY="${APP_API_KEY:-$(openssl rand -hex 16)}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
OWNER_REPO="$(echo "$REPO_URL" | sed -E 's#https://github.com/(.*)\.git#\1#' | tr 'A-Z' 'a-z')"

for b in docker k3d kubectl helm; do command -v "$b" >/dev/null || { echo "missing $b"; exit 1; }; done

echo "==> 1/7 cluster"
k3d cluster list | grep -q '^sre ' || k3d cluster create -c k3d/cluster.yaml
kubectl config use-context k3d-sre

echo "==> 2/7 point manifests at your repo (commit & push this change to main via PR/first push)"
sed -i.bak "s#https://github.com/OWNER/REPO.git#${REPO_URL}#g" argocd/*.yaml
sed -i.bak "s#ghcr.io/OWNER/REPO#ghcr.io/${OWNER_REPO}#g" k8s/base/kustomization.yaml
rm -f argocd/*.bak k8s/base/*.bak

echo "==> 3/7 namespaces + secrets (kept out of Git)"
kubectl create namespace leaky-app --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl -n leaky-app create secret generic leaky-app-secrets \
  --from-literal=APP_API_KEY="$APP_API_KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-alert-secrets \
  --from-literal=SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/7 ArgoCD ${ARGOCD_VERSION}"
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -f argocd/project.yaml -f argocd/application.yaml

echo "==> 5/7 Helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "==> 6/7 Loki + Alloy + kube-prometheus-stack (Grafana)"
helm upgrade --install loki grafana/loki -n monitoring -f observability/loki-values.yaml --wait --timeout 10m
helm upgrade --install alloy grafana/alloy -n monitoring -f observability/alloy-values.yaml --wait
kubectl -n monitoring create configmap grafana-alerting \
  --from-file=observability/grafana-alerting/ --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_alert=1 -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap sre-overview-dashboard \
  --from-file=observability/dashboards/sre-overview.json --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -
helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f observability/kube-prometheus-stack-values.yaml \
  --set-string grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" --wait --timeout 15m

echo "==> 7/7 done"
cat <<MSG

ArgoCD admin password : $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}

Access:
  kubectl -n argocd port-forward svc/argocd-server 8443:443     -> https://localhost:8443  (admin)
  kubectl -n monitoring port-forward svc/kps-grafana 3000:80    -> http://localhost:3000   (admin)
  kubectl -n leaky-app port-forward svc/leaky-app 8081:80       -> http://localhost:8081

Next: commit the rewritten argocd/ + k8s/base files to your repo's main branch.
MSG
