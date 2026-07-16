# The Last Jenkins Job

> *A Jenkins pipeline that bootstraps a full GitOps platform — Terraform, ingress-nginx, ArgoCD, Prometheus, Grafana — and then removes itself in the final step.*

Built as a portfolio project for brushing up on SRE/DevOps skills. The joke lands with anyone who's lived through the Jenkins → GitOps migration: you used the old tool to replace itself with the new way of doing things.

---

## What It Does

```
Stage 1:  Environment check (kubectl, docker)
Stage 2:  Install Terraform, Helm, ArgoCD CLI
Stage 3:  terraform init + validate + plan
Stage 4:  terraform apply → deploys ingress-nginx, ArgoCD, Prometheus, Grafana
Stage 5:  Platform health checks (won't self-destruct if unhealthy)
Stage 6:  Seed Gitea platform-config repo (the GitOps source of truth)
Stage 7:  Register repo with ArgoCD, deploy app-of-apps
Stage 8:  Final validation
Stage 9:  Write platform manifest + tombstone
Stage 10: 💀 Jenkins removes itself via Docker socket
```

After Stage 10, Jenkins is gone. The platform it built keeps running. ArgoCD watches Gitea and manages everything from here on.

---

## Prerequisites

- **Docker Desktop** with Kubernetes enabled — this is required and off by default:
  1. Open Docker Desktop → **Settings** → **Kubernetes**
  2. Tick **Enable Kubernetes**
  3. Click **Apply & Restart** and wait ~2 minutes for the cluster to come up
- **Docker Compose** (included with Docker Desktop)
- **~6 GB RAM** available
- Ports free: `8080`, `8888`, `3001`, `2222`, `3000`, `8090`, `9090`

Verify Kubernetes is running before starting:
```bash
kubectl config get-contexts
# Should show a row with NAME = docker-desktop

kubectl get nodes
# Should show a Ready node
```

---

## Quick Start

### 1. Clone and start the stack

```bash
git clone <this-repo> the-last-jenkins-job
cd the-last-jenkins-job

docker compose up -d
```

Everything is ready in ~15 seconds (Gitea is lightweight — no more waiting for GitLab).

### 2. Open the live dashboard

```
http://localhost:8888
```

This shows pipeline progress in real time and outlives Jenkins (by design).

### 3. Log in to Jenkins

```
http://localhost:8080
Username: admin
Password: admin
```

### 4. Run the pipeline

Click **Build Now** in Jenkins and watch the dashboard at `http://localhost:8888`.

---

## After Jenkins Is Gone

Once Stage 10 completes, Jenkins removes itself. The platform keeps running:

| Service    | URL                       | Credentials                                 |
|------------|---------------------------|---------------------------------------------|
| ArgoCD     | http://localhost:8090     | admin / (see `argocd-initial-admin-secret`) |
| Grafana    | http://localhost:3000     | admin / `gitops-era-begins`                 |
| Prometheus | http://localhost:9090     | —                                           |
| Gitea      | http://localhost:3001     | gitea / `gitops-forever`                    |
| Dashboard  | http://localhost:8888     | Still running, shows tombstone              |

Get the ArgoCD password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Explore what's deployed:
```bash
kubectl get namespaces -l last-jenkins-job=true
helm list --all-namespaces
kubectl get applications -n argocd
```

---

## Project Structure

```
the-last-jenkins-job/
├── Jenkinsfile                          ← The main event
├── docker-compose.yml                   ← Gitea + Jenkins + Dashboard
├── jenkins/
│   ├── Dockerfile                       ← Jenkins image with kubectl, docker CLI
│   ├── plugins.txt                      ← Jenkins plugins
│   └── init.groovy.d/
│       └── basic-setup.groovy           ← Auto-configures Jenkins on startup
├── terraform/
│   ├── providers.tf                     ← Kubernetes + Helm providers
│   ├── main.tf                          ← All infrastructure resources
│   ├── variables.tf
│   └── outputs.tf
├── scripts/
│   ├── install-deps.sh                  ← Stage 2: install terraform/helm/argocd
│   ├── health-check.sh                  ← Stage 5: validate the platform
│   └── farewell.sh                      ← Stage 10: the self-destruct
├── platform-config/
│   ├── apps/
│   │   ├── app-of-apps.yaml             ← Root ArgoCD Application
│   │   └── sample-app.yaml             ← "Hello from GitOps" demo app
│   └── workloads/
│       └── hello-gitops/
│           └── deployment.yaml         ← Nginx page deployed by ArgoCD
└── dashboard/
    ├── index.html                       ← Live pipeline progress dashboard
    └── nginx.conf                       ← Proxies Jenkins API + serves state files
```

---

## How The Self-Destruct Works

Jenkins is granted access to the host Docker socket (`/var/run/docker.sock`) via the volume mount in `docker-compose.yml`. In Stage 10, `farewell.sh` runs:

```bash
nohup bash -c "sleep 3 && docker rm -f jenkins-controller" > /dev/null 2>&1 &
```

This schedules container removal in a background process, giving the Jenkins pipeline enough time to report the final stage as complete before the container is killed. The pipeline shows ✅ on Stage 10, then Jenkins vanishes.

The dashboard continues running (it's a separate nginx container) and shows the tombstone.

---

## Tech Stack Demonstrated

| Area                     | Technology                                  |
|--------------------------|---------------------------------------------|
| CI/CD                    | Jenkins (Declarative Pipeline, Groovy)      |
| IaC                      | Terraform (Kubernetes + Helm providers)     |
| GitOps                   | ArgoCD (app-of-apps pattern)                |
| Container Orchestration  | Kubernetes (Docker Desktop)                 |
| Package Management       | Helm                                        |
| Networking               | ingress-nginx (LoadBalancer, Ingress)       |
| Observability            | Prometheus + Grafana (kube-prometheus-stack)|
| Source Control           | Gitea (self-hosted Git server)              |
| Containerisation         | Docker, Docker Compose                      |

---

## Troubleshooting

**Gitea admin user missing / Jenkins can't clone**
The `gitea-init` container creates the admin and pushes the code. If it failed, re-run it:
```bash
docker compose run --rm gitea-init
```

**Terraform can't reach the cluster**
```bash
kubectl config get-contexts
# Make sure docker-desktop context exists and is reachable
```

**Jenkins can't reach Gitea**
Both are on the `last-jenkins-net` Docker network. Use the hostname `gitea` from within Jenkins (not `localhost`).

**Self-destruct didn't work**
Check if the Docker socket is mounted:
```bash
docker exec jenkins-controller docker ps
```
If that fails, the socket isn't available. Verify the volume in `docker-compose.yml` and restart.

To manually remove Jenkins after the fact:
```bash
docker compose stop jenkins
docker compose rm -f jenkins
```

---

## CV Description

> Built *The Last Jenkins Job* — a fully working Jenkins pipeline that bootstraps a local Kubernetes platform (ingress-nginx, ArgoCD, Prometheus, Grafana) using Terraform and Helm, then removes itself in the final step using the Docker socket. A tongue-in-cheek commentary on the GitOps transition, and a reference implementation covering CI/CD, IaC, GitOps, networking, and observability in a single self-contained demo.

---

*"Using the master's tools to dismantle the master's house."*
