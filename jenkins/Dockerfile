FROM jenkins/jenkins:lts-jdk17

# ── The Jenkins container that will outlive its purpose ────────────
# Pre-installed with everything needed to bootstrap a GitOps platform
# and then quietly remove itself from the equation.

USER root

# System dependencies: Docker CLI (for self-destruct), kubectl, utils
# gosu: used by entrypoint.sh to drop from root → jenkins after fixing socket GID
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    unzip \
    jq \
    python3 \
    python3-pip \
    dnsutils \
    netcat-openbsd \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (not daemon — we mount the host socket)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# kubectl — the key to the kingdom we're about to build
# ARCH uses dpkg --print-architecture so this builds correctly on both amd64 and arm64
RUN KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
    && ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Add jenkins user to docker group (GID may be updated at runtime by entrypoint.sh
# to match the host socket — this just ensures the group exists in the container)
RUN groupadd -f docker && usermod -aG docker jenkins

# ── Jenkins plugins ────────────────────────────────────────────────
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# ── Auto-configuration Groovy scripts ─────────────────────────────
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# ── Skip the setup wizard — we know what we're doing ──────────────
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# ── Entrypoint: detects Docker socket GID, adds jenkins to the right
# group, then drops to the jenkins user via gosu.
# The container must start as root for groupmod/usermod to work.
# Jenkins itself runs as the jenkins user (uid 1000).
COPY entrypoint.sh /usr/local/bin/jenkins-entrypoint.sh
RUN chmod +x /usr/local/bin/jenkins-entrypoint.sh

# Stay as root — entrypoint.sh will drop to jenkins via gosu
USER root
ENTRYPOINT ["/usr/local/bin/jenkins-entrypoint.sh"]
