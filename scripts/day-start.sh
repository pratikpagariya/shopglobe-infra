#!/usr/bin/env bash
# Re-bootstrap the cluster after a terraform apply.
#
# Everything here is idempotent, so it is safe to re-run. It exists because
# `terraform destroy` at the end of each day is the right call at ~$8/day, and
# that makes "rebuild the whole environment from code" a thing you do often
# enough to script.
#
# Terraform builds the cluster. This builds everything ON it that is not yet
# managed by ArgoCD. Once day 4's app-of-apps is live, most of this moves into
# git and ArgoCD reconciles it instead -- which is the point of GitOps.
set -euo pipefail

CLUSTER="${CLUSTER:-shopglobe-prod-eks}"
REGION="${AWS_REGION:-ap-south-1}"
GITOPS="${GITOPS:-/mnt/c/Users/prati/Documents/shopglobe-gitops}"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

say "kubeconfig for $CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes -o custom-columns='NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,POOL:.metadata.labels.workload'

say "EKS addons"
for addon in eks-pod-identity-agent aws-ebs-csi-driver; do
  if aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$addon" --region "$REGION" >/dev/null 2>&1; then
    echo "  $addon already present"
  else
    echo "  creating $addon"
    aws eks create-addon --cluster-name "$CLUSTER" --addon-name "$addon" --region "$REGION" >/dev/null
  fi
done
# Pod Identity delivers credentials via a node-local agent. Without that
# DaemonSet the associations exist in AWS and do nothing in the cluster.
kubectl -n kube-system rollout status ds/eks-pod-identity-agent --timeout=180s

say "namespaces, quotas, limits, network policies"
kubectl apply -f "$GITOPS/bootstrap/namespaces/"

say "storage class"
kubectl apply -f "$GITOPS/bootstrap/storage/"
# Two default StorageClasses is an error, so demote the one EKS ships.
kubectl patch storageclass gp2 -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

say "helm repos"
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null 2>&1 || true
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null

say "cluster-autoscaler"
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system -f "$GITOPS/bootstrap/values/cluster-autoscaler.yaml" --wait --timeout 5m

say "aws-load-balancer-controller"
# vpcId changes on every rebuild, so read it from state rather than hardcoding.
VPC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../iac/stacks/prod" && terraform output -raw vpc_id)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f "$GITOPS/bootstrap/values/aws-lb-controller.yaml" \
  --set vpcId="$VPC" --wait --timeout 5m

say "external-secrets"
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set crds.enabled=true --set serviceAccount.name=external-secrets \
  --set tolerations[0].key=workload --set tolerations[0].operator=Equal \
  --set tolerations[0].value=platform --set tolerations[0].effect=NoSchedule \
  --wait --timeout 5m
kubectl apply -f "$GITOPS/bootstrap/secrets/" 2>/dev/null || echo "  (no secret store manifests yet)"

say "status"
kubectl get ns -l env
kubectl -n kube-system get deploy cluster-autoscaler aws-load-balancer-controller 2>/dev/null || true
kubectl get clustersecretstore 2>/dev/null || true

say "ready. Pod Identity check:"
echo "  kubectl run pi -n jenkins --rm -it --restart=Never --image=amazon/aws-cli \\"
echo "    --overrides='{\"spec\":{\"serviceAccountName\":\"jenkins\"}}' -- sts get-caller-identity"
