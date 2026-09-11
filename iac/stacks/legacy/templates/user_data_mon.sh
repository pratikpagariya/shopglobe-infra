#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io docker-compose-v2 unzip curl
systemctl enable --now docker
mkdir -p /opt/monitoring
# prometheus.yml and docker-compose.yml are written BY HAND over SSM.
# That is step 24, and it is the block that fixes your monitoring gap.
