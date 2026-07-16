#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  health-check.sh — Stage 5: Checking the pulse                 ║
# ║  Jenkins will not self-destruct until the platform is healthy.  ║
# ║  It has standards.                                              ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

PASS=0
FAIL=0

check() {
    local description="$1"
    local command="$2"
    local allow_warn="${3:-false}"

    printf "  %-50s" "${description}..."
    if eval "${command}" &>/dev/null; then
        echo "✅"
        PASS=$((PASS + 1))
    elif [ "${allow_warn}" = "warn" ]; then
        echo "⚠️  (warning — non-fatal)"
        PASS=$((PASS + 1))
    else
        echo "❌"
        FAIL=$((FAIL + 1))
    fi
}

wait_for_pods() {
    local label="$1"
    local namespace="$2"
    local timeout="${3:-180s}"
    kubectl wait --for=condition=Ready pods \
        -l "${label}" \
        -n "${namespace}" \
        --timeout="${timeout}" &>/dev/null
}

echo ""
echo "🔍 Platform Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📦 Namespaces:"
check "ingress-nginx namespace exists" "kubectl get ns ingress-nginx"
check "argocd namespace exists"        "kubectl get ns argocd"
check "monitoring namespace exists"    "kubectl get ns monitoring"
check "apps namespace exists"          "kubectl get ns apps"

echo ""
echo "⛵ Helm Releases:"
check "ingress-nginx release deployed" "helm status ingress-nginx -n ingress-nginx"
check "argocd release deployed"        "helm status argocd -n argocd"
check "prometheus-stack deployed"      "helm status kube-prometheus-stack -n monitoring"

echo ""
echo "💚 Pod Readiness:"
check "ingress-nginx controller ready" \
    "wait_for_pods 'app.kubernetes.io/name=ingress-nginx' ingress-nginx 120s"
check "argocd-server ready" \
    "wait_for_pods 'app.kubernetes.io/name=argocd-server' argocd 300s"
check "argocd-repo-server ready" \
    "wait_for_pods 'app.kubernetes.io/name=argocd-repo-server' argocd 300s"
check "prometheus ready" \
    "wait_for_pods 'app=kube-prometheus-stack-prometheus' monitoring 300s" "warn"
check "grafana ready" \
    "wait_for_pods 'app.kubernetes.io/name=grafana' monitoring 300s" "warn"

echo ""
echo "🌐 Network:"
check "kubectl can reach kube-system" \
    "kubectl get pods -n kube-system --field-selector=status.phase=Running"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    echo "❌ ${FAIL} health check(s) failed. ${PASS} passed."
    echo ""
    echo "Jenkins will NOT self-destruct until the platform it built is healthy."
    echo "Fix the issues above and re-run the pipeline."
    echo ""
    echo "Current pod state:"
    kubectl get pods --all-namespaces -l last-jenkins-job=true 2>/dev/null || \
        kubectl get pods -n argocd; kubectl get pods -n monitoring; kubectl get pods -n ingress-nginx
    exit 1
else
    echo "✅ All ${PASS} health checks passed."
    echo ""
    echo "The platform is healthy. Jenkins may now proceed with its final act."
    echo ""
fi
