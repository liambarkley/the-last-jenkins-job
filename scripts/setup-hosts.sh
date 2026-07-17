#!/bin/bash
# setup-hosts.sh — Add .localhost entries so the platform URLs work without port-forwarding.
# Run once: sudo ./scripts/setup-hosts.sh
# Safe to run multiple times (idempotent).

HOSTS_FILE="/etc/hosts"
MARKER="# the-last-jenkins-job"

ENTRIES=(
    "127.0.0.1 argocd.localhost"
    "127.0.0.1 grafana.localhost"
    "127.0.0.1 prometheus.localhost"
    "127.0.0.1 hello.localhost"
)

if grep -q "$MARKER" "$HOSTS_FILE" 2>/dev/null; then
    echo "✅ Hosts entries already present — nothing to do."
    exit 0
fi

echo "✍️  Adding platform hosts to $HOSTS_FILE..."
{
    echo ""
    echo "$MARKER"
    for entry in "${ENTRIES[@]}"; do
        echo "$entry"
    done
} >> "$HOSTS_FILE"

echo "✅ Done. These domains now resolve to localhost:"
for entry in "${ENTRIES[@]}"; do
    echo "   http://$(echo "$entry" | awk '{print $2}')"
done
