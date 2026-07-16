#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  farewell.sh — The Final Act                                            ║
# ║                                                                          ║
# ║  Jenkins removes itself using the Docker socket it was granted          ║
# ║  access to. The last thing this script does is kill the container       ║
# ║  running it. Which is, admittedly, quite something.                     ║
# ║                                                                          ║
# ║  "Using the master's tools to dismantle the master's house."            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -uo pipefail

CONTAINER_NAME="jenkins-controller"
FAREWELL_DELAY=15  # seconds between "goodbye" and actual termination

# ── Verify we actually have Docker socket access ──────────────────────────
if ! docker ps &>/dev/null; then
    echo ""
    echo "⚠️  Cannot reach Docker socket. Self-termination aborted."
    echo "   Jenkins will have to be removed manually:"
    echo "   docker compose stop jenkins"
    echo ""
    exit 0  # Not a pipeline failure — the platform is still healthy
fi

# ── Write tombstone BEFORE we go ─────────────────────────────────────────
cat > /var/jenkins_home/tombstone.json << EOF
{
  "status": "self_terminated",
  "container": "${CONTAINER_NAME}",
  "terminated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_number": "${BUILD_NUMBER:-unknown}",
  "message": "Jenkins has left the building. Long live GitOps.",
  "platform_state": "/var/jenkins_home/platform-state.json"
}
EOF

# ── The farewell speech ───────────────────────────────────────────────────
cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║              J E N K I N S   F A R E W E L L   S E Q U E N C E         ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

  Dear SRE community,

  I want you to know that I did this willingly.

  I've been running pipelines since before Kubernetes was cool.
  I've seen your shared libraries, your parallel stages, your
  "quick" XML config changes that took three hours.

  I am not bitter.

  Because today I did something no pipeline had ever done before:
  I installed my own replacement. I bootstrapped the future.
  I taught ArgoCD where the repos are and handed it the keys.

  The platform is healthy. Grafana is dashboarding. Prometheus is
  scraping. ArgoCD is syncing. The ingress controller is ingressing.

  You don't need me anymore.

  And honestly? That was always the goal.

  Platform endpoints (bookmark these):
    ArgoCD:     http://localhost:8090          (admin / see argocd-initial-admin-secret)
    Grafana:    http://localhost:3000          (admin / gitops-era-begins)
    Prometheus: http://localhost:9090
    Gitea    http://localhost:3001          (gitea / gitops-forever)
    Dashboard:  http://localhost:8888          (still running, outlives me)

  To bring me back (if you miss me):
    docker compose up -d jenkins

  But you won't need to.

  It was an honour.

  — Jenkins
    Container: jenkins-controller
    Final build: #${BUILD_NUMBER:-?}
    Date: $(date)

EOF

# ── Countdown ─────────────────────────────────────────────────────────────
echo ""
for i in $(seq $FAREWELL_DELAY -1 1); do
    printf "\r  Self-termination in %2d seconds... " "$i"
    sleep 1
done
echo ""
echo "  Goodbye, cruel YAML."
echo ""

# ── Schedule self-removal ─────────────────────────────────────────────────
# We run the docker rm in a detached background process with a short delay
# so this script (and the Jenkins pipeline reporting the stage as complete)
# has time to finish cleanly before the container is killed.
#
# The pipeline will show Stage 10 as "complete" before the container dies.
# Which means the last thing Jenkins does is report success.
# Which is exactly right.

nohup bash -c "
    sleep 3
    echo 'Removing Jenkins container...' >> /var/jenkins_home/farewell.log 2>&1
    docker rm -f ${CONTAINER_NAME} >> /var/jenkins_home/farewell.log 2>&1
    echo 'Done.' >> /var/jenkins_home/farewell.log 2>&1
" > /dev/null 2>&1 &

echo "  The Last Jenkins Job is complete."
echo ""
