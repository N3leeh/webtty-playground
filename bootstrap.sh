#!/usr/bin/env bash

set -euo pipefail

# Main playbook
PLAYBOOK="webtty.yml"

# Immer aus dem Repo-Verzeichnis heraus arbeiten, damit ansible.cfg,
# relative Pfade und vars/ gefunden werden.
cd "$(dirname "$(readlink -f "$0")")"

if ! command -v ansible &> /dev/null; then
  echo "ansible not found. Attempt to install."
  if [ -x "/usr/bin/apt-get" ]; then
    apt-get update && apt-get install -y ansible python3-passlib
  elif rpm -q -f /bin/ls >/dev/null 2>&1; then
    yum install -y ansible python3-passlib
  else
    echo "Don't know this package system (neither RPM nor DEB)."
    exit 1
  fi
fi

# Rollen und Collections aus requirements.yml installieren
ansible-galaxy role install -r requirements.yml -p roles
ansible-galaxy collection install -r requirements.yml

ansible-playbook "$PLAYBOOK" "$@"
