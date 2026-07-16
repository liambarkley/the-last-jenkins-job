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
        # Run insecure locally — no TLS termination needed on Docker Desktop
        insecure = true
        # ClusterIP — ingress-nginx handles external routing.
        # LoadBalancer on Docker Desktop leaves EXTERNAL-IP <pending> forever
        # and the load-balancer-cleanup finalizer blocks namespace deletion.
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts            = ["argocd.localhost"]
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
        # Note: server.insecure is set via server.insecure = true above (adds --insecure flag).
        # Do NOT also set it in params — ArgoCD Helm v6.11.1 template does a boolean
        # eq comparison that fails when the value comes through as a YAML string.
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

  depends_on = [helm_release.ingress_nginx]
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

  depends_on = [helm_release.ingress_nginx]
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
