#!/usr/bin/env bash
# Install k3s from /etc/rancher/k3s/config.yaml. Pass "agent" on workers.
set -euo pipefail

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${1:-server}" sh -
