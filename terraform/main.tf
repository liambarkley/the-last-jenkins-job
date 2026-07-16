# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  THE LAST JENKINS JOB — Main Terraform Configuration                    ║
# ║                                                                          ║
# ║  This file deploys an entire GitOps platform to local Kubernetes.       ║
# ║  It is run once, by Jenkins, and then Jenkins is gone.                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

locals {
  # Labels applied to everything — a permanent record of how this was built
  common_labels = {
    "managed-by"        = "terraform"
    "bootstrapped-by"   = "jenkins"
    "last-jenkins-job"  = "true"
    "gitops-ready"      = "true"
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# NAMESPACES — Carving up the cluster
# ═══════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name   = "ingress-nginx"
    labels = local.common_labels
    annotations = {
      "last-jenkins-job/purpose" = "Network ingress layer"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name   = "argocd"
    labels = local.common_labels
    annotations = {
      "last-jenkins-job/purpose" = "GitOps engine — takes over when Jenkins leaves"
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = local.common_labels
    annotations = {
      "last-jenkins-job/purpose" = "Prometheus + Grafana observability stack"
    }
  }
}

resource "kubernetes_namespace" "apps" {
  metadata {
    name   = "apps"
    labels = local.common_labels
    annotations = {
      "last-jenkins-job/purpose" = "Application workloads managed by ArgoCD"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# INGRESS-NGINX — The traffic cop
# Installed first; everything else benefits from it
# ═══════════════════════════════════════════════════════════════════════════

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
        }
        metrics = {
          enabled = true
          # ServiceMonitor disabled here — the CRD is installed by kube-prometheus-stack
          # which runs after ingress-nginx. Prometheus scrapes via pod annotations instead.
          serviceMonitor = {
            enabled = false
          }
        }
        config = {
          "use-forwarded-headers" = "true"
          "proxy-body-size"       = "50m"
        }
        # Resource limits appropriate for a local cluster
        resources = {
          requests = { cpu = "100m", memory = "90Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }
    })
  ]

  timeout          = 300
  wait             = true
  wait_for_jobs    = true
  cleanup_on_fail  = true
}

# ── Admission webhook grace period ────────────────────────────────────────────
# ingress-nginx registers a ValidatingWebhookConfiguration that Kubernetes calls
# whenever an Ingress is created. The webhook endpoint becomes reachable a few
# seconds AFTER the pod reports Ready. Without this delay, any chart that creates
# an Ingress immediately after ingress-nginx (ArgoCD, kube-prometheus-stack)
# gets a "context deadline exceeded" from the webhook and fails.
resource "null_resource" "ingress_webhook_ready" {
  depends_on = [helm_release.ingress_nginx]

  provisioner "local-exec" {
    command = "sleep 20"
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# ARGO CD — The successor
# The GitOps engine. Once this is running and watching the platform-config
# repo, Jenkins is truly redundant.
# ═══════════════════════════════════════════════════════════════════════════

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version

  values = [
    yamlencode({
      global = {
        logging = {
          level  = "info"
          format = "json"
        }
      }

      server = {
        # ClusterIP — ingress-nginx handles external routing.
        # LoadBalancer on Docker Desktop leaves EXTERNAL-IP <pending> forever
        # and the load-balancer-cleanup finalizer blocks namespace deletion.
        service = {
          type = "ClusterIP"
        }
        ingress = {
          # Disabled — the chart ignores the hosts override and defaults to
          # argocd.example.com regardless. We create the Ingress explicitly below.
          enabled = false
        }
        metrics = {
          enabled = true
          # ServiceMonitor CRD is installed by kube-prometheus-stack.
          # ArgoCD and kube-prometheus-stack deploy in parallel, so the CRD
          # may not exist yet when ArgoCD installs. Disable to avoid race.
          serviceMonitor = {
            enabled = false
          }
        }
      }

      configs = {
        # In ArgoCD Helm 6.x, insecure mode must be set via configs.params,
        # not server.insecure. The server.insecure Helm value targets a different
        # code path that doesn't reliably take effect in 6.11.1 — the server
        # continues to redirect HTTP→HTTPS, causing ERR_TOO_MANY_REDIRECTS.
        # configs.params writes directly to argocd-cmd-params-cm which the server
        # reads at startup.
        params = {
          "server.insecure" = "true"
        }
        cm = {
          # Tell ArgoCD where to find its own UI
          url = "http://argocd.localhost"
          # Enable status badge — must be boolean (not string "true")
          # ArgoCD Helm _helpers.tpl does `eq .val true` (bool comparison)
          "statusbadge.enabled" = true
        }
        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv" = <<-EOT
            p, role:admin, applications, *, */*, allow
            p, role:admin, clusters, get, *, allow
            p, role:admin, repositories, *, *, allow
            g, admin, role:admin
          EOT
        }
      }

      # High-availability is overkill for a local demo
      # Single replicas keep resource usage low
      repoServer = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }

      applicationSet = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "250m", memory = "128Mi" }
        }
      }
    })
  ]

  timeout          = 600
  wait             = true
  wait_for_jobs    = true
  cleanup_on_fail  = true

  depends_on = [null_resource.ingress_webhook_ready]
}

# ── ArgoCD Ingress ────────────────────────────────────────────────────────
# Created explicitly rather than via the Helm chart's server.ingress because
# the chart ignores the hosts override and always defaults to argocd.example.com.
# Explicit resource = full control, no surprises.
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels    = local.common_labels
    annotations = {
      # ArgoCD runs in insecure mode (HTTP on 8080). Without backend-protocol=HTTP,
      # nginx may try to negotiate HTTPS upstream and the connection fails silently.
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "nginx.ingress.kubernetes.io/ssl-redirect"     = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = "argocd.localhost"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd, null_resource.ingress_webhook_ready]
}

# ═══════════════════════════════════════════════════════════════════════════
# KUBE-PROMETHEUS-STACK — See everything, question nothing
# Prometheus for metrics, Grafana for dashboards, Alertmanager for noise
# ═══════════════════════════════════════════════════════════════════════════

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version

  values = [
    yamlencode({
      grafana = {
        adminPassword = var.grafana_admin_password

        service = {
          type = "ClusterIP"
        }

        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = ["grafana.localhost"]
        }

        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }

        # Pre-load community dashboards by Grafana ID
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = "Platform"
                type            = "file"
                disableDeletion = false
                editable        = true
                options         = { path = "/var/lib/grafana/dashboards/default" }
              }
            ]
          }
        }

        dashboards = {
          default = {
            kubernetes-cluster = { gnetId = 7249,  revision = 1, datasource = "Prometheus" }
            argocd             = { gnetId = 14584, revision = 1, datasource = "Prometheus" }
            ingress-nginx      = { gnetId = 9614,  revision = 1, datasource = "Prometheus" }
          }
        }
      }

      prometheus = {
        prometheusSpec = {
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
          retention       = "1d"    # demo only — no need for long retention
          scrapeInterval  = "60s"   # default is 15s; 60s halves CPU load dramatically
          resources = {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = ["prometheus.localhost"]
        }
      }

      # Alertmanager is noise in a local demo — disable entirely
      alertmanager = {
        enabled = false
      }

      coreDns = {
        enabled = true
      }
    })
  ]

  # Don't block Terraform waiting for pods — pulling 8+ images on Apple Silicon
  # can take 10+ minutes. health-check.sh (stage 5) handles readiness instead.
  timeout          = 120   # just needs to submit the release, not wait for pods
  wait             = false
  wait_for_jobs    = false
  cleanup_on_fail  = true

  depends_on = [null_resource.ingress_webhook_ready]
}

# ═══════════════════════════════════════════════════════════════════════════
# A note in the cluster — Jenkins was here
# ═══════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "last_jenkins_job_manifest" {
  metadata {
    name      = "last-jenkins-job-manifest"
    namespace = "default"
    labels    = local.common_labels
    annotations = {
      "last-jenkins-job/completed-at" = timestamp()
    }
  }

  data = {
    "README" = <<-EOT
      This cluster was bootstrapped by The Last Jenkins Job.

      What was deployed:
        - ingress-nginx  (networking)
        - ArgoCD         (GitOps — now in control)
        - Prometheus     (metrics)
        - Grafana        (dashboards)

      Jenkins ran once. Then Jenkins removed itself.
      Everything you see is now managed by ArgoCD + Gitea.

      This ConfigMap is the only evidence Jenkins was ever here.
      (Besides the git history, obviously.)
    EOT

    "services.txt" = <<-EOT
      ArgoCD:     http://argocd.localhost  (or kubectl port-forward)
      Grafana:    http://grafana.localhost (admin / gitops-era-begins)
      Prometheus: http://prometheus.localhost
      Gitea:   http://localhost:3001   (gitea / gitops-forever)
    EOT
  }

  depends_on = [
    helm_release.argocd,
    helm_release.kube_prometheus_stack,
  ]
}
