#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  entrypoint.sh — Jenkins container startup                              ║
# ║                                                                          ║
# ║  Runs as root briefly to wire up Docker socket access, then drops       ║
# ║  to the jenkins user via gosu. Jenkins itself never runs as root.       ║
# ║                                                                          ║
# ║  The problem this solves:                                                ║
# ║  The Docker socket mounted from the host has a GID that may not         ║
# ║  match the 'docker' group inside the container. Rather than running     ║
# ║  as root (blunt) or hardcoding a GID (brittle), we detect the actual    ║
# ║  socket GID at startup and make jenkins a member of that group.         ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -eo pipefail

DOCKER_SOCK="/var/run/docker.sock"

if [ -S "$DOCKER_SOCK" ]; then
    SOCKET_GID=$(stat -c '%g' "$DOCKER_SOCK")

    # If no group in the container owns this GID, create one or update docker
    if ! getent group "$SOCKET_GID" > /dev/null 2>&1; then
        # Try to update the existing docker group to the host GID first.
        # If that fails (docker group doesn't exist), create docker-host.
        groupmod -g "$SOCKET_GID" docker 2>/dev/null \
            || groupadd -g "$SOCKET_GID" docker-host
    fi

    # Add jenkins to whichever group now owns the socket
    SOCKET_GROUP=$(getent group "$SOCKET_GID" | cut -d: -f1)
    usermod -aG "$SOCKET_GROUP" jenkins

    echo "[entrypoint] Docker socket GID=${SOCKET_GID}, group=${SOCKET_GROUP} — jenkins added."
else
    echo "[entrypoint] No Docker socket found at ${DOCKER_SOCK} — self-destruct will be skipped."
fi

# Drop privileges and start Jenkins under its own user.
# gosu re-reads the group database so the updated group membership takes effect immediately.
exec gosu jenkins /usr/bin/tini -- /usr/local/bin/jenkins.sh
