#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# THIS SCRIPT IS THE "BEFORE". No image, no version pinning, no rollback, and
# no way to know what is running except by logging in. Every deploy re-runs it
# on a fresh instance. That is the evidence for your scorecard.

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3-pip unzip curl jq

curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install

NE=1.8.2
curl -sSL "https://github.com/prometheus/node_exporter/releases/download/v$${NE}/node_exporter-$${NE}.linux-amd64.tar.gz" | tar xz -C /tmp
mv /tmp/node_exporter-$${NE}.linux-amd64/node_exporter /usr/local/bin/
useradd -rs /bin/false node_exporter || true
cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=node_exporter
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /opt/shopglobe
aws s3 cp "s3://${artifact_bucket}/app.tar.gz" /tmp/app.tar.gz --region ${region}
tar xzf /tmp/app.tar.gz -C /opt/shopglobe
cd /opt/shopglobe
python3.12 -m venv .venv
.venv/bin/pip install --no-cache-dir -r requirements.txt

DB_JSON=$(aws secretsmanager get-secret-value --secret-id "${db_secret_arn}" --region ${region} --query SecretString --output text)
DB_USER=$(echo "$DB_JSON" | jq -r .username)
DB_PASS=$(echo "$DB_JSON" | jq -r .password)

cat > /opt/shopglobe/.env <<ENVEOF
ENV=legacy
MARKET=in
LOG_LEVEL=INFO
AWS_REGION=${region}
DATABASE_URL=postgresql+asyncpg://$${DB_USER}:$${DB_PASS}@${db_host}:5432/shopglobe
AUTH_URL=http://localhost:8001
CATALOG_URL=http://localhost:8002
JWT_SECRET=legacy-stack-secret
ENVEOF
chmod 600 /opt/shopglobe/.env

# THREE SERVICES ON ONE HOST, ports assigned by hand. You cannot scale catalog
# without also scaling auth. That sentence is a scorecard row.
write_unit() {
  cat > /etc/systemd/system/$1.service <<UNIT
[Unit]
Description=$1
After=network-online.target
[Service]
WorkingDirectory=/opt/shopglobe
EnvironmentFile=/opt/shopglobe/.env
Environment=SERVICE_NAME=$2
Environment=PORT=$3
Environment=PYTHONPATH=/opt/shopglobe
ExecStart=/opt/shopglobe/.venv/bin/python -m services.$1.main
Restart=always
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
UNIT
}

write_unit edge_gateway edge-gateway 8000
write_unit auth_svc     auth-svc     8001
write_unit catalog_svc  catalog-svc  8002

systemctl daemon-reload
systemctl enable --now node_exporter edge_gateway auth_svc catalog_svc
