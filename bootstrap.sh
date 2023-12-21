#!/usr/bin/env bash

set -e

# Main playbook
PLAYBOOK="webtty.yml"

if ! command -v ansible &> /dev/null;then
  echo "ansible not found. Attempt to install."
  if dpkg -S /bin/ls >/dev/null 2>&1;then
    apt update && apt install -y ansible
  elif rpm -q -f /bin/ls >/dev/null 2>&1;then
    yum install ansible
  else
    echo "Don't know this package system (neither RPM nor DEB)."
    exit 1
  fi
fi
ansible-galaxy role install -r requirements.yml
ansible-playbook $PLAYBOOK