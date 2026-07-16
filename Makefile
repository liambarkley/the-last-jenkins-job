# The Last Jenkins Job — Makefile
# One command to rule them all.

.PHONY: start stop reset hosts open logs push

# ── start ─────────────────────────────────────────────────────────────────────
# First-time setup: add hosts, start everything, open the dashboard.
# Jenkins will take it from here.
start: hosts
	@echo "🚀 Starting The Last Jenkins Job..."
	docker compose up -d
	@echo ""
	@echo "⏳ Waiting for Jenkins to start..."
	@until curl -sf http://localhost:8080/login > /dev/null 2>&1; do sleep 2; done
	@echo "✅ Jenkins is up. Opening dashboard..."
	@sleep 1
	open http://localhost:8888
	@echo ""
	@echo "  Dashboard: http://localhost:8888"
	@echo "  Jenkins:   http://localhost:8080  (admin / $(shell docker compose run --rm -T jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo 'see jenkins logs'))"
	@echo ""
	@echo "  Trigger the pipeline in Jenkins, then watch the dashboard."
	@echo "  When it's done, the platform will be live at:"
	@echo "    ArgoCD:     http://argocd.localhost"
	@echo "    Grafana:    http://grafana.localhost  (admin / gitops-era-begins)"
	@echo "    Prometheus: http://prometheus.localhost"
	@echo "    Gitea:      http://localhost:3001     (gitea / gitops-forever)"

# ── hosts ─────────────────────────────────────────────────────────────────────
# Add .localhost entries to /etc/hosts. Requires sudo once.
hosts:
	@if grep -q "the-last-jenkins-job" /etc/hosts 2>/dev/null; then \
		echo "✅ Hosts already configured"; \
	else \
		echo "📝 Adding platform hosts (requires sudo)..."; \
		sudo bash scripts/setup-hosts.sh; \
	fi

# ── open ──────────────────────────────────────────────────────────────────────
# Open all platform UIs in your browser.
open:
	@echo "🌐 Opening platform UIs..."
	open http://localhost:8888
	open http://argocd.localhost
	open http://grafana.localhost
	open http://prometheus.localhost
	open http://localhost:3001

# ── push ──────────────────────────────────────────────────────────────────────
# Re-seed Gitea with the current platform-config. Run after any file change.
push:
	docker compose run --rm gitea-init

# ── logs ──────────────────────────────────────────────────────────────────────
logs:
	docker compose logs -f jenkins

# ── stop ──────────────────────────────────────────────────────────────────────
stop:
	docker compose down

# ── reset ─────────────────────────────────────────────────────────────────────
# Full tear-down. Removes volumes too — next start is a clean slate.
reset:
	@echo "⚠️  This will destroy all data. Press Ctrl+C to abort, Enter to continue."
	@read _
	docker compose down -v
	@echo "✅ Reset complete. Run 'make start' to begin again."
