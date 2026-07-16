FROM jenkins/jenkins:lts-jdk17

# ── The Jenkins container that will outlive its purpose ────────────
# Pre-installed with everything needed to bootstrap a GitOps platform
# and then quietly remove itself from the equation.

USER root

# System dependencies: Docker CLI (for self-destruct), kubectl, utils
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
RUN KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Add jenkins user to docker group so it can talk to the socket
RUN groupadd -f docker && usermod -aG docker jenkins

# ── Jenkins plugins ────────────────────────────────────────────────
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# ── Auto-configuration Groovy scripts ─────────────────────────────
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# ── Skip the setup wizard — we know what we're doing ──────────────
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

USER jenkins
