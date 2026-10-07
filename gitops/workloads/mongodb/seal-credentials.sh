#!/bin/bash
# Seal MongoDB credentials with the committed Sealed Secrets public cert.
# Requires kubeseal. Passwords come from the environment (do not commit them).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CERT="${ROOT}/gitops/sealed-secrets-cert.pem"
OUT="${ROOT}/gitops/workloads/mongodb/manifests/mongodb-credentials-sealed.yaml"
mkdir -p "$(dirname "$OUT")"

: "${MONGODB_ROOT_PASSWORD:?set MONGODB_ROOT_PASSWORD}"
: "${MONGODB_PASSWORD:?set MONGODB_PASSWORD}"
: "${MONGODB_REPLICA_SET_KEY:?set MONGODB_REPLICA_SET_KEY}"

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal is required (https://github.com/bitnami/sealed-secrets/releases)" >&2
  exit 1
fi

kubectl create secret generic mongodb-credentials \
  --namespace default \
  --from-literal=mongodb-root-password="${MONGODB_ROOT_PASSWORD}" \
  --from-literal=mongodb-passwords="${MONGODB_PASSWORD}" \
  --from-literal=mongodb-replica-set-key="${MONGODB_REPLICA_SET_KEY}" \
  --dry-run=client -o yaml |
  kubeseal --cert "$CERT" --format yaml > "$OUT"

echo "Wrote ${OUT}"
