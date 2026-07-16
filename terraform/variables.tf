variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use (docker-desktop for Docker Desktop)"
  type        = string
  default     = "docker-desktop"
}

variable "ingress_nginx_version" {
  description = "ingress-nginx Helm chart version"
  type        = string
  default     = "4.10.1"
}

variable "argocd_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "6.11.1"
}

variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "59.1.0"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "gitops-era-begins"
  sensitive   = true
}
