#!/usr/bin/env bash
# Usage: source ./set-secrets.sh
if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
  [ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa -q
  export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
fi
SECRET_FILE=~/.azdemo-db-password
if [ -z "${DB_PASSWORD:-}" ]; then
  [ -f "$SECRET_FILE" ] || (umask 077; openssl rand -base64 18 > "$SECRET_FILE")
  export DB_PASSWORD="$(cat "$SECRET_FILE")"
fi
echo "SSH_PUBLIC_KEY set: ${SSH_PUBLIC_KEY:0:20}...  DB_PASSWORD set: yes"
