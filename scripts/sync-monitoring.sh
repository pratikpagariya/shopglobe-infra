#!/usr/bin/env bash
# Push monitoring/ from git onto the legacy monitoring instance, then reload.
#
# WHY THIS EXISTS: config typed by hand on a box exists only on that box. When
# the box dies, so does the config, and nobody can rebuild it. Authoring in git
# and pushing means the instance holds no unique state -- it is replaceable.
#
# This is the push model (what Ansible does). The pull model bakes config into
# the AMI or fetches it at boot from S3. On Kubernetes (day 5) neither applies:
# the config is a ConfigMap rendered from the gitops repo, and the pod is
# disposable by construction. Same principle, three mechanisms.
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/monitoring"

command -v jq >/dev/null || { echo "jq required: sudo apt install -y jq" >&2; exit 1; }
[ -d "$SRC" ] || { echo "no $SRC directory" >&2; exit 1; }

IID=$(aws ec2 describe-instances --region "$REGION" \
      --filters Name=tag:Role,Values=monitoring Name=instance-state-name,Values=running \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)

[ -n "$IID" ] && [ "$IID" != "None" ] || { echo "no running monitoring instance" >&2; exit 1; }
echo ">> syncing to $IID"

# Build one remote script that writes each file, then reloads.
# NOTE: SSM runs /bin/sh (dash), not bash. POSIX only.
REMOTE="set -eu
mkdir -p /opt/monitoring/load
"
for f in "$SRC"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  case "$name" in
    *.js) dest="/opt/monitoring/load/$name" ;;
    *)    dest="/opt/monitoring/$name" ;;
  esac
  # Quoted heredoc delimiter: content is written literally, no shell expansion.
  REMOTE="$REMOTE
cat > $dest <<'SYNC_EOF'
$(cat "$f")
SYNC_EOF"
done

REMOTE="$REMOTE
cd /opt/monitoring
docker compose up -d
sleep 3
# Hot-reload beats a restart: it keeps the TSDB in memory and drops no scrapes.
curl -sf -X POST localhost:9090/-/reload && echo 'prometheus reloaded' || echo 'reload failed - check config syntax'
curl -s localhost:9090/api/v1/targets | grep -o '\"health\":\"[a-z]*\"' | sort | uniq -c"

CID=$(aws ssm send-command --instance-ids "$IID" --region "$REGION" \
      --document-name AWS-RunShellScript \
      --parameters "$(jq -n --arg c "$REMOTE" '{commands:[$c]}')" \
      --query Command.CommandId --output text)

echo ">> command $CID dispatched, waiting..."
STATUS=Pending
for _ in $(seq 1 20); do
  STATUS=$(aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" \
           --region "$REGION" --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 3
done

echo ">> status: $STATUS"
aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" --region "$REGION" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text

[ "$STATUS" = "Success" ] || exit 1
