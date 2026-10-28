#!/usr/bin/env bash
# Creates the local overlay's database credentials once, with a random password. The file is git-ignored
# and never leaves this machine. An existing file is kept: PostgreSQL reads POSTGRES_PASSWORD only when it
# initialises an empty volume, so a new password would not match the data already in the cluster.
set -euo pipefail
cd "$(dirname "$0")/.."

f=gitops/overlays/local/secrets/postgres.env
if [[ -f $f ]]; then
  echo "local-secrets: $f already exists, keeping it"
  exit 0
fi

umask 077
# Hex keeps the password URL-safe: it is embedded in DATABASE_URL.
printf 'POSTGRES_USER=taskflow\nPOSTGRES_DB=taskflow\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)" >"$f"
echo "local-secrets: created $f (mode 600, git-ignored)"
