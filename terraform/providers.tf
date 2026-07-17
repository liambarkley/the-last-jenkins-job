# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  THE LAST JENKINS JOB — Terraform Providers                              ║
# ║                                                                          ║
# ║  Target: Docker Desktop Kubernetes (local)                               ║
# ║  Provisions: ingress-nginx, ArgoCD, kube-prometheus-stack via Helm       ║
# ╚══════════════════════════════════════════════════════════════════════════╝

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # State lives on the Jenkins volume — survives container restarts,
  # but will be gone once Jenkins is gone. Which is sort of the point.
  backend "local" {
    path = "/var/jenkins_home/terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
