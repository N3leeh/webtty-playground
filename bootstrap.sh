#!/usr/bin/env bash

set -e

# Main playbook
PLAYBOOK="webtty.yml"

if ! command -v ansible &> /dev/null;then
  echo "ansible not found. Attempt to install."
  if dpkg -S /bin/ls >/dev/null 2>&1;then
    sudo apt update && sudo apt install -y ansible python3-pip
    pip3 install --user github3.py
  elif rpm -q -f /bin/ls >/dev/null 2>&1;then
    sudo yum install ansible
  else
    echo "Don't know this package system (neither RPM nor DEB)."
    exit 1
  fi
else
  ansible 
fi