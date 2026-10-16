#!/usr/bin/env bash
# Everything after `terraform apply`, in one command. Run it AFTER the apply,
# never instead of it: an apply deserves a human reading its plan first.
#
#   1/6 day-start.sh  kubeconfig, EKS add-ons, namespaces + quotas + policies,
#                     storage class, cluster-autoscaler, LB controller,
#                     External Secrets, the bootstrap ExternalSecrets
#   2/6 Kyverno       before ArgoCD, so the ValidatingPolicy kind exists by the
#                     time ArgoCD syncs policies/
#   3/6 ArgoCD        + the root app-of-apps; from here on, git drives the cluster
#   4/6 Jenkins       image into ECR, its secrets from AWS, the controller
#   5/6 seed job      generates all 9 jobs from the Job DSL in shopglobe-apps
#   6/6 8 builds      a fresh ECR has no images, so Jenkins rebuilds them and
#                     ArgoCD deploys dev as each gitops commit lands
#
# Idempotent: safe to re-run after a partial failure.
#   eval "$(aws configure export-credentials --profile shopglobe --format env)"
#   bash scripts/day-up.sh               # everything
#   bash scripts/day-up.sh --no-builds   # stop after the seed job
#   bash scripts/day-up.sh --preflight   # check tools/credentials/paths only
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:-shopglobe-prod-eks}"
GITOPS="${GITOPS:-/mnt/c/Users/prati/Documents/shopglobe-gitops}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_REGION="$REGION" CLUSTER GITOPS  # day-start.sh reads all three

# Every pin in one place. Bump here, not at a command line.
KYVERNO_CHART=3.9.1  # = Kyverno v1.19.1
ARGOCD_CHART=10.9.5  # = ArgoCD v3.5.3
JENKINS_CHART=5.9.64
SERVICES="edge-gateway auth-svc catalog-svc cart-svc order-svc payment-worker notify-svc media-svc"

MODE="${1:-all}"
case "$MODE" in
  all | --no-builds | --preflight) ;;
  *) echo "usage: $0 [--no-builds | --preflight]" >&2; exit 2 ;;
esac

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
START=$SECONDS
took() { printf '    (%dm%02ds so far)\n' $(((SECONDS - START) / 60)) $(((SECONDS - START) % 60)); }

# Helm treats a local folder named like the chart (jenkins/, kyverno/) as the
# chart itself and silently ignores --repo -- hit for real on 2026-10-14.
# Working from an empty directory makes that impossible.
WORK="$(mktemp -d)"
PF=""
cleanup() { if [ -n "$PF" ]; then kill "$PF" 2>/dev/null || true; fi; rm -rf "$WORK"; }
trap cleanup EXIT
cd "$WORK"

# ---------------------------------------------------------------------------
say "preflight"
for t in aws kubectl helm docker python3 curl terraform; do
  command -v "$t" >/dev/null || die "$t is not installed"
done
docker info >/dev/null 2>&1 || die "the Docker daemon is not running (needed to push the Jenkins image)"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) ||
  die 'no AWS credentials. Run: eval "$(aws configure export-credentials --profile shopglobe --format env)"'
ECR="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
[ -f "$GITOPS/argocd/bootstrap/root.yaml" ] || die "gitops repo not found at $GITOPS (set GITOPS=...)"
JENKINS_TAG=$(python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["controller"]["image"]["tag"])' \
  "$GITOPS/jenkins/values.yaml")
JENKINS_IMAGE="$ECR/shopglobe-prod-jenkins:$JENKINS_TAG"
STATUS=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster.status --output text 2>/dev/null || echo "NOT FOUND")
echo "  account $ACCOUNT, region $REGION"
echo "  cluster $CLUSTER: $STATUS"
echo "  gitops  $GITOPS"
echo "  jenkins image $JENKINS_IMAGE"
if [ "$MODE" = --preflight ]; then
  echo "  preflight OK"
  exit 0
fi
[ "$STATUS" = ACTIVE ] || die "cluster is $STATUS -- run terraform apply in iac/stacks/prod first"

# ---------------------------------------------------------------------------
say "1/6 day-start.sh"
bash "$HERE/day-start.sh"
took

say "2/6 Kyverno $KYVERNO_CHART"
helm upgrade --install kyverno kyverno --repo https://kyverno.github.io/kyverno/ \
  --version "$KYVERNO_CHART" -n kyverno --create-namespace \
  -f "$GITOPS/bootstrap/values/kyverno.yaml" --wait --timeout 8m
took

say "3/6 ArgoCD $ARGOCD_CHART + root app"
# OCI from ghcr.io: the classic repo URL serves the .tgz from GitHub's
# release-asset storage, which timed out mid-install on 2026-10-14.
helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --version "$ARGOCD_CHART" -n argocd --create-namespace \
  -f "$GITOPS/bootstrap/values/argocd.yaml" --wait --timeout 10m
kubectl apply -f "$GITOPS/argocd/bootstrap/root.yaml"
took

say "4/6 Jenkins $JENKINS_CHART"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR" >/dev/null
if aws ecr describe-images --region "$REGION" --repository-name shopglobe-prod-jenkins \
  --image-ids imageTag="$JENKINS_TAG" >/dev/null 2>&1; then
  echo "  $JENKINS_TAG already in ECR"
else
  # ECR is destroyed with the stack, so a fresh cluster has no Jenkins image.
  # Push the local copy while Docker still has it; build only as a last
  # resort -- a rebuild re-resolves every plugin version.
  if ! docker image inspect "$JENKINS_IMAGE" >/dev/null 2>&1; then
    echo "  no local copy -- building from $GITOPS/jenkins (5-10 min)"
    docker build -t "$JENKINS_IMAGE" "$GITOPS/jenkins"
  fi
  docker push "$JENKINS_IMAGE" >/dev/null
  echo "  pushed $JENKINS_IMAGE"
fi
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f "$GITOPS/jenkins/external-secret.yaml" >/dev/null
kubectl -n jenkins wait externalsecret/jenkins-secrets --for=condition=Ready --timeout=120s >/dev/null ||
  die "jenkins-secrets did not sync -- does shopglobe/prod/jenkins exist in Secrets Manager?"
helm upgrade --install jenkins jenkins --repo https://charts.jenkins.io \
  --version "$JENKINS_CHART" -n jenkins -f "$GITOPS/jenkins/values.yaml" \
  --set-file controller.JCasC.configScripts.shopglobe="$GITOPS/jenkins/jenkins.yaml" \
  --wait --timeout 10m
took

# ---------------------------------------------------------------------------
say "5/6 seed job"
# The admin password goes into a netrc file, not onto curl's command line,
# where anyone on the machine could read it in `ps`.
printf 'machine localhost login admin password %s\n' \
  "$(kubectl -n jenkins get secret jenkins-secrets -o jsonpath='{.data.JENKINS_ADMIN_PASSWORD}' | base64 -d)" \
  >"$WORK/netrc"
chmod 600 "$WORK/netrc"
J=http://localhost:18080
kubectl -n jenkins port-forward svc/jenkins 18080:8080 >/dev/null 2>&1 &
PF=$!
for _ in $(seq 1 30); do curl -sf -o /dev/null "$J/login" && break; sleep 2; done
curl -sf -o /dev/null "$J/login" || die "Jenkins is not answering on $J"

jget() { curl -sf --netrc-file "$WORK/netrc" "$J$1"; }
# Jenkins' CSRF protection: every POST needs a fresh crumb, sent with the same
# session cookie that fetched it.
jpost() {
  local c
  c=$(curl -sf --netrc-file "$WORK/netrc" -c "$WORK/cookies" "$J/crumbIssuer/api/json" |
    python3 -c 'import sys, json; d = json.load(sys.stdin); print(d["crumbRequestField"] + ": " + d["crumb"])')
  curl -sf -o /dev/null --netrc-file "$WORK/netrc" -b "$WORK/cookies" -H "$c" -X POST "$J$1"
}
next_build() { jget "$1/api/json?tree=nextBuildNumber" | python3 -c 'import sys, json; print(json.load(sys.stdin)["nextBuildNumber"])'; }
# Wait for ONE specific build number. "lastBuild" can still be the previous
# run while the new one sits in the queue waiting for its agent pod.
wait_build() {
  local out
  for _ in $(seq 1 180); do
    out=$(jget "$1/$2/api/json?tree=building,result" 2>/dev/null || true)
    if grep -q '"building":false' <<<"$out"; then
      python3 -c 'import sys, json; print(json.load(sys.stdin)["result"])' <<<"$out"
      return
    fi
    sleep 5
  done
  echo TIMEOUT
}

n=$(next_build /job/seed)
jpost /job/seed/build
result=$(wait_build /job/seed "$n")
[ "$result" = SUCCESS ] || die "seed #$n finished $result -- open it in the Jenkins UI (see the port-forward line below)"
echo "  seed #$n SUCCESS"
took

# ---------------------------------------------------------------------------
say "6/6 build all 8 services"
if [ "$MODE" = --no-builds ]; then
  echo "  skipped (--no-builds)"
else
  declare -A num
  for s in $SERVICES; do
    num[$s]=$(next_build "/job/shopglobe/job/$s")
    jpost "/job/shopglobe/job/$s/buildWithParameters"
  done
  echo "  8 builds queued; they run in parallel and the Cluster Autoscaler may add nodes"
  failed=0
  for s in $SERVICES; do
    r=$(wait_build "/job/shopglobe/job/$s" "${num[$s]}")
    printf '  %-15s #%-3s %s\n' "$s" "${num[$s]}" "$r"
    [ "$r" = SUCCESS ] || failed=1
  done
  [ "$failed" = 0 ] || echo "  some builds did not succeed -- open them in the Jenkins UI before going on"
fi
took

say "done in $(((SECONDS - START) / 60))m$(((SECONDS - START) % 60))s"
cat <<'EOF'
  ArgoCD now deploys dev as each gitops commit lands (it polls git every ~3 min).

  dev apps: kubectl get applications -n argocd | grep -- -dev
  ALB:      kubectl -n shopglobe-dev get ingress edge-gateway   (ADDRESS appears ~2-3 min after sync)
  Jenkins:  kubectl -n jenkins port-forward svc/jenkins 8080:8080       -> http://localhost:8080  (admin)
  ArgoCD:   kubectl -n argocd port-forward svc/argocd-server 8081:80    -> http://localhost:8081  (admin)
            kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
EOF
