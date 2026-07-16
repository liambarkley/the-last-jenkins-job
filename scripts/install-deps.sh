#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  install-deps.sh — Stage 2: Arming Jenkins with modern tools    ║
# ║  Terraform, Helm, ArgoCD CLI                                    ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

TF_VERSION="${TF_VERSION:-1.8.0}"
HELM_VERSION="${HELM_VERSION:-3.14.0}"

# Install into jenkins_home/bin — writable by the jenkins user
INSTALL_DIR="/var/jenkins_home/bin"
mkdir -p "${INSTALL_DIR}"
export PATH="${INSTALL_DIR}:${PATH}"

# Detect architecture (Apple Silicon = aarch64 → arm64 in download URLs)
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)          TF_ARCH="amd64" ; HELM_ARCH="amd64" ; ARGOCD_ARCH="amd64" ;;
  aarch64 | arm64) TF_ARCH="arm64" ; HELM_ARCH="arm64" ; ARGOCD_ARCH="arm64" ;;
  *) echo "  [✗] Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

log()  { echo "  [+] $*"; }
skip() { echo "  [✓] $* (already installed)"; }
fail() { echo "  [✗] $*" >&2; exit 1; }

echo ""
echo "🔧 Installing platform toolchain (arch: ${ARCH})..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Terraform ─────────────────────────────────────────────────────
if command -v terraform &>/dev/null && terraform version | grep -q "v${TF_VERSION}"; then
    skip "Terraform ${TF_VERSION}"
else
    log "Installing Terraform ${TF_VERSION} (${TF_ARCH})..."
    TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip"
    TF_ZIP="/tmp/terraform.zip"

    curl -fsSL "${TF_URL}" -o "${TF_ZIP}" || fail "Failed to download Terraform"
    unzip -o "${TF_ZIP}" -d "${INSTALL_DIR}/" terraform
    chmod +x "${INSTALL_DIR}/terraform"
    rm -f "${TF_ZIP}"

    log "Terraform installed: $(terraform version | head -1)"
fi

# ── Helm ──────────────────────────────────────────────────────────
if command -v helm &>/dev/null && helm version --short | grep -q "v${HELM_VERSION}"; then
    skip "Helm ${HELM_VERSION}"
else
    log "Installing Helm ${HELM_VERSION} (${HELM_ARCH})..."
    HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
    TMP_DIR=$(mktemp -d)

    curl -fsSL "${HELM_URL}" | tar xz -C "${TMP_DIR}"
    mv "${TMP_DIR}/linux-${HELM_ARCH}/helm" "${INSTALL_DIR}/helm"
    chmod +x "${INSTALL_DIR}/helm"
    rm -rf "${TMP_DIR}"

    log "Helm installed: $(helm version --short)"
fi

# ── ArgoCD CLI ────────────────────────────────────────────────────
if command -v argocd &>/dev/null; then
    skip "ArgoCD CLI"
else
    log "Installing ArgoCD CLI (${ARGOCD_ARCH})..."
    ARGOCD_URL="https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${ARGOCD_ARCH}"

    curl -sSfL "${ARGOCD_URL}" -o "${INSTALL_DIR}/argocd" || fail "Failed to download ArgoCD CLI"
    chmod +x "${INSTALL_DIR}/argocd"

    log "ArgoCD CLI installed: $(argocd version --client --short 2>/dev/null | head -1)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎒 Jenkins is now carrying the full weight of its own replacement."
echo "   It will install it all. Then it will leave."
echo ""
