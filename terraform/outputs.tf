output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "monitoring_namespace" {
  description = "Monitoring namespace"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "ingress_nginx_namespace" {
  description = "ingress-nginx namespace"
  value       = kubernetes_namespace.ingress_nginx.metadata[0].name
}

output "platform_summary" {
  description = "Summary of deployed services"
  sensitive   = true  # grafana_admin_password is embedded in the value
  value = {
    argocd     = "http://argocd.localhost (kubectl port-forward svc/argocd-server 8090:80 -n argocd)"
    grafana    = "http://grafana.localhost — admin / ${var.grafana_admin_password}"
    prometheus = "http://prometheus.localhost"
    note       = "Jenkins bootstrapped this. Jenkins is now gone. Long live GitOps."
  }
}
