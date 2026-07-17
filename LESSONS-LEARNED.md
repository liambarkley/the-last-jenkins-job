# The Last Jenkins Job — Build Notes

Things that went wrong, why they went wrong, and what fixed them. Not a highlight reel — this is the actual journey.

---

## 1. Kubernetes namespace deletion is asynchronous

The cleanup stage deleted namespaces, then immediately tried to recreate them via Terraform. It failed with `namespace already exists`.

`kubectl delete namespace` returns as soon as the deletion is *requested*, not when it's done. Namespaces enter a `Terminating` state and sit there for up to 60 seconds while Kubernetes drains finalizers. Terraform saw a namespace in `Terminating` and treated it as existing — because it technically is.

The fix is to wait explicitly:
```bash
kubectl wait --for=delete namespace/argocd --timeout=60s
```

This is Kubernetes' eventual consistency model in practice. Most operations queue work and return immediately. "Deleted" just means "deletion requested."

---

## 2. LoadBalancer services create finalizers that block namespace deletion

The `monitoring` namespace got stuck in `Terminating` permanently — `kubectl delete namespace monitoring` returned fine but the namespace never actually went away.

`kube-prometheus-stack` creates services with `type: LoadBalancer`. On Docker Desktop these get an external IP, but they also acquire a `service.kubernetes.io/load-balancer-cleanup` finalizer. When the namespace is deleted, Kubernetes tries to run a cloud cleanup routine for the load balancer — which doesn't exist locally — so the finalizer never resolves and the namespace hangs forever.

Two things fixed it: switching Prometheus and Grafana services to `ClusterIP` in Terraform values (avoiding the finalizer entirely), and adding an explicit finalizer-strip before every namespace deletion:

```bash
kubectl patch namespace monitoring \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
```

Finalizers are Kubernetes' pre-delete hook mechanism, and they're easy to miss until a cloud controller attaches one to a resource that has no equivalent in your local environment.

---

## 3. kubectl was silently talking to Jenkins instead of Kubernetes

The cleanup loop was returning exit 0 for every `kubectl get namespace` even when the namespaces didn't exist — so it ran forever.

The `KUBECONFIG` env var was set to `/tmp/kubeconfig` in the pipeline, but that file was created in a *separate* `sh` block later in the same stage. Jenkins runs each `sh` block in its own shell, so the env var was set but the file wasn't there when kubectl ran. Without a valid kubeconfig, kubectl fell back to its default server, which on port 8080 hit Jenkins' own web UI. The HTML response came back with exit 0, making every existence check return "yes."

Merging both blocks into one — with kubeconfig setup unconditionally at the top — fixed it. The broader lesson: tools that fail open silently are harder to debug than tools that fail loudly. kubectl didn't error, it just talked to the wrong server.

---

## 4. Resources in the `default` namespace survive "nuke everything" cleanup

After adding a ConfigMap to Terraform, subsequent runs failed because Terraform's state referenced it but the resource had drifted — the namespace-based cleanup didn't touch it.

The ConfigMap lives in `default`, which the cleanup never deletes. Everything in `argocd`, `monitoring`, `ingress-nginx`, and `apps` gets torn down, but `default` is invisible to that strategy. Terraform's local state still knew about the ConfigMap from the previous run and hit a conflict on the next apply.

Explicitly deleting it in the cleanup stage sorted it:
```bash
kubectl delete configmap last-jenkins-job-manifest -n default --ignore-not-found
```

`default` is a quiet survivor in any cleanup that works by namespace. Worth keeping in mind when designing teardown logic.

---

## 5. ArgoCD CLI gRPC doesn't work reliably over kubectl port-forward on Docker Desktop

Stage 7 timed out every time at around 32 seconds trying `argocd login` then `argocd repo add`. The error was `gRPC connection not ready: context deadline exceeded`.

The ArgoCD CLI uses gRPC (HTTP/2). Tunnelling that through `kubectl port-forward` over Docker Desktop's virtualised network layer is fragile — the connection handshakes but the stream stalls. The `--grpc-web` fallback flag (which should drop to HTTP/1.1) didn't help either.

The eventual fix was removing the ArgoCD CLI entirely. ArgoCD's operator pattern means Kubernetes itself is the API — the CLI is just a convenience wrapper. Registering the Gitea repository is as simple as applying a Secret with the right label:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: platform-config-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://host.docker.internal:3001/gitea/platform-config.git
  username: gitea
  password: gitops-forever
```

ArgoCD picks it up automatically. No login, no port-forward, no gRPC.

---

## 6. Jenkins' Groovy sandbox blocks standard Java methods

Stage 9 failed at runtime with:
```
Scripts not permitted to use method java.lang.String stripLeading
```

`String.stripLeading()` was introduced in Java 11. Jenkins' declarative pipeline runs inside a Groovy sandbox with an allowlist of permitted methods, and that method was never added to the list. The code compiled fine and looked valid — the rejection only happened at execution time.

Switching to Groovy's regex-based `replaceAll` worked:
```groovy
"".replaceAll(/^\s+/, '')
```

Declarative Jenkins pipelines aren't regular Groovy. The sandbox is deliberately restrictive and lags behind Java releases. When something inexplicably fails in a pipeline, the sandbox whitelist is always worth checking first — and the fix is usually to express the same thing differently rather than trying to add a method approval.

---

## 7. Terraform's local state doesn't know about kubectl/helm deletions

Terraform would sometimes plan zero changes on a fresh run because its state file said everything existed — even after the cleanup stage had deleted it all with `kubectl` and `helm` directly.

Terraform's local backend is just a file. When resources are destroyed outside of Terraform, the state file doesn't update. On the next run, `terraform plan` detects the drift and replans correctly, but the stale state caused ordering problems and confusing output.

The simplest fix: delete the state alongside everything else at the start of each run:
```bash
rm -rf /var/jenkins_home/terraform-work
```

Each run starts from a clean `terraform init`. For a pipeline that tears down and rebuilds the entire platform on every run, throwing away state and letting the plan re-derive it is more reliable than trying to keep the state in sync with out-of-band changes.

---

## 8. ArgoCD can't reach Gitea using `localhost` or Docker Compose service names

ArgoCD (running inside Kubernetes pods) couldn't connect to Gitea at `localhost:3001` or `gitea:3001`.

`localhost` inside a Kubernetes pod is that pod's own loopback — not the host machine. `gitea` is a Docker Compose service name that resolves only within the Compose network. Kubernetes pods and Docker Compose containers live in separate network namespaces with no shared DNS.

`host.docker.internal` is Docker Desktop's way of resolving to the host machine's loopback from inside any container, whether Compose or Kubernetes. Since Gitea is bound to `localhost:3001` on the host, this works from both environments:
```
http://host.docker.internal:3001/gitea/platform-config.git
```

When mixing Docker Compose and Kubernetes locally it's worth sketching out which names resolve from where before writing any URLs. The topology isn't obvious.

---

## 9. `wait = false` on a Helm release hides readiness from downstream stages

`kube-prometheus-stack` deployed without error according to Terraform but Prometheus pods weren't up when the health check stage ran against them shortly after.

`wait = false` tells Helm to return as soon as the release is *applied* rather than waiting for pods to become *ready*. It was set that way intentionally — kube-prometheus-stack installs a lot of CRDs and takes several minutes to fully start, which was blowing up pipeline run times. But the downstream health check didn't know that and treated "not yet ready" as a failure.

The trade-off between pipeline speed and strict sequencing is real here. The approach that worked: keep `wait = false` on the slow component and make the health check smart enough to treat Prometheus as a warning rather than a hard failure. ingress-nginx and ArgoCD are on the critical path and use `wait = true`; Prometheus can lag behind.

---

## 10. ingress-nginx admission webhook isn't reachable immediately after the pod is Ready

After ingress-nginx deployed successfully, both ArgoCD and kube-prometheus-stack failed immediately with:
```
failed calling webhook "validate.nginx.ingress.kubernetes.io": context deadline exceeded
```

ingress-nginx registers a `ValidatingWebhookConfiguration` — Kubernetes calls this webhook before admitting any Ingress resource. The webhook endpoint is a TLS server inside the ingress-nginx pod, and it takes several seconds to start accepting connections *after* the pod reports `Ready`. ArgoCD and kube-prometheus-stack both try to create Ingress resources right after ingress-nginx finishes deploying, and they hit the webhook before it's actually reachable.

A `null_resource` with a 20-second sleep gated behind ingress-nginx, with both downstream charts depending on it, gave the webhook enough time:

```hcl
resource "null_resource" "ingress_webhook_ready" {
  depends_on = [helm_release.ingress_nginx]
  provisioner "local-exec" {
    command = "sleep 20"
  }
}
```

Pod readiness probes tell Kubernetes when a pod is ready to receive application traffic. They say nothing about whether control-plane integrations like admission webhooks are ready to be called. The two can be meaningfully different, especially in the seconds immediately after startup.

---

## 11. Docker CLI group permissions and socket file permissions are separate checks

The farewell script couldn't reach the Docker socket even though it was mounted at `/var/run/docker.sock` and the container image added the `jenkins` user to the `docker` group.

Part of the confusion was that `docker version --format {{.Client.Version}}` — used as a health check in stage 1 — returns the compiled-in client version without ever contacting the daemon. It looked like Docker was working when it wasn't.

The actual problem: the `docker` group GID inside the container is assigned by the Dockerfile at image build time. On macOS with Docker Desktop, the socket file's group on the host has a different GID. When the socket is mounted into the container, the GID mismatch means the `jenkins` user isn't actually in the group that owns the socket, and the Docker CLI gets permission denied.

The fix was to bypass the Docker CLI entirely and call the Docker Engine REST API directly using `curl --unix-socket`:

```bash
# Check connectivity
curl -sf --unix-socket /var/run/docker.sock http://localhost/_ping

# Remove the container
curl -sf --unix-socket /var/run/docker.sock \
  -X DELETE "http://localhost/containers/jenkins-controller?force=true"
```

The Docker CLI is a wrapper around a REST API. When the wrapper fails due to environment mismatches, the underlying API is often still reachable.

---

## 12. Two separate permission layers control Unix socket access

Even after switching to `curl --unix-socket`, the socket check still failed.

There are two independent permission checks when connecting to a Unix socket:

1. The **application-level check** — the Docker CLI verifies group membership before touching the socket at all. Bypassed by using `curl` directly.
2. The **kernel file permission check** — connecting to a Unix socket requires write permission on the socket file itself. On some Docker Desktop versions the mounted socket comes in as `srw-rw----` (no world access) rather than `srw-rw-rw-`. `curl` respects this just as the CLI does.

Both were blocking, but they look identical from the outside — "can't reach the socket" — which made the second one invisible until the first was fixed.

The initial fix was to run the container as root — blunt, but it unblocked development. That immediately introduced a third issue: git 2.35+ refuses to operate in directories owned by a different uid (the "dubious ownership" check). Workspace directories owned by uid 1000 (jenkins) are silently ignored when accessed as root, causing `fatal: not in a git directory` before a single stage ran.

Stacking `git config --global --add safe.directory '*'` on top of `user: root` solved it temporarily, but the result was Jenkins running as root with a wildcard git trust override — two security anti-patterns in one entrypoint.

The proper fix is a startup shim that does the GID work before dropping privileges:

```bash
#!/bin/bash
# entrypoint.sh — runs as root briefly, drops to jenkins via gosu

if [ -S /var/run/docker.sock ]; then
    SOCKET_GID=$(stat -c '%g' /var/run/docker.sock)
    if ! getent group "$SOCKET_GID" > /dev/null 2>&1; then
        groupmod -g "$SOCKET_GID" docker 2>/dev/null \
            || groupadd -g "$SOCKET_GID" docker-host
    fi
    SOCKET_GROUP=$(getent group "$SOCKET_GID" | cut -d: -f1)
    usermod -aG "$SOCKET_GROUP" jenkins
fi

exec gosu jenkins /usr/bin/tini -- /usr/local/bin/jenkins.sh
```

The Dockerfile sets `USER root` and `ENTRYPOINT` to this script. The container starts as root long enough to detect the actual socket GID, update group membership, then drops to `jenkins` (uid 1000) for everything that follows. Jenkins itself never runs as root. The git safe.directory override isn't needed because the process running git owns the workspace directories.

Two security controls, both invisible until you change execution context. Understanding the layering — socket file permissions vs. group membership, and process uid vs. directory ownership — is what separates a real fix from stacking workarounds.

---

## 13. `|| true` on a wait command silently turns a timeout into a success

After the namespace deletion fix from lesson 1, the cleanup used `kubectl wait --for=delete namespace/X --timeout=60s || true`. This worked most of the time, but on a second consecutive run — where kube-prometheus-stack was still in the middle of terminating — both `ingress-nginx` and `monitoring` exceeded the 60-second timeout. `|| true` swallowed the error and the script moved on. Terraform immediately attempted to create those namespaces and hit:

```
Error: object is being deleted: namespaces "ingress-nginx" already exists
Error: object is being deleted: namespaces "monitoring" already exists
```

The race condition that lesson 1 was supposed to fix had just been given a shorter time window and a silent exit.

kube-prometheus-stack installs a significant number of CRDs, operators, and pods. When those are mid-termination after a previous run, the namespace can take 2+ minutes to fully clear — well beyond any 60-second assumption.

The fix is a polling loop that confirms the namespace is actually gone rather than trusting a timed command to be sufficient:

```bash
for ns in ingress-nginx argocd monitoring apps; do
    while kubectl get namespace "$ns" > /dev/null 2>&1; do
        sleep 5
    done
done
```

`|| true` is useful for "I expect this might not exist." It's the wrong pattern for "I need this to be gone before I continue." The distinction matters.

---

## Patterns that kept showing up

**Kubernetes is eventually consistent by design.** Almost no operation completes synchronously. Deletes, creates, status changes — everything is queued. Assuming an operation is complete when the command returns is a reliable way to introduce race conditions.

**The Jenkins Groovy sandbox is not regular Groovy.** It has an allowlist of permitted methods that lags behind Java releases. When a pipeline fails in an unexpected way at runtime, the sandbox is worth checking before anything else.

**CLIs are wrappers, not the only path.** The ArgoCD CLI (gRPC over port-forward) and the Docker CLI (group-based socket access) both failed in ways their underlying APIs didn't. Knowing what a tool is actually doing — and being willing to go one layer down — is what makes the difference when the wrapper misbehaves.

**Cleanup is harder than creation.** Every interesting problem in this project surfaced during teardown: async deletion, stuck finalizers, state drift, namespace blind spots. Building something is straightforward; building something that can cleanly undo itself is where the real edge cases live.
