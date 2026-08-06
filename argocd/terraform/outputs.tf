output "cluster_name" {
  description = "EKS cluster name — use with 'aws eks update-kubeconfig'"
  value       = module.eks.cluster_name
}

output "kube_config_raw" {
  description = "In-memory kubeconfig — use 'aws eks update-kubeconfig --name <cluster>' for local use"
  value       = local.eks_kubeconfig
  sensitive   = true
}

output "get_credentials_command" {
  description = "Run this after apply to configure kubectl and Headlamp"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region} --alias argocd-demo-${var.environment}"
}

output "argocd_server_url" {
  description = "ArgoCD LoadBalancer URL — computed during apply"
  value       = local.argocd_external_url
}

output "argocd_login_command" {
  description = "ArgoCD CLI login command — fill in the URL from argocd_server_url"
  value       = "argocd login <EXTERNAL-URL> --username admin --insecure"
}

output "get_gateway_token" {
  description = "Inspect the ArgoCD token the gateway is using"
  value       = "kubectl get secret argocd-gateway-token -n octopus-argocd-gateway -o jsonpath='{.data.ARGOCD_AUTH_TOKEN}' --context argocd-demo-${var.environment} | base64 --decode && echo"
}

output "get_gateway_logs" {
  description = "Tail gateway logs to verify Octopus connection"
  value       = "kubectl logs -l app.kubernetes.io/name=octopus-argocd-gateway -n octopus-argocd-gateway --context argocd-demo-${var.environment} -f"
}

output "k8s_agent_target_id" {
  description = "Octopus deployment target ID for the Kubernetes agent"
  value       = octopusdeploy_kubernetes_agent_deployment_target.k8s_agent.id
}

output "get_k8s_agent_logs" {
  description = "Tail Kubernetes agent logs to verify Octopus connection"
  value       = "kubectl logs -l app.kubernetes.io/name=kubernetes-agent -n ${var.kubernetes_agent_namespace} --context argocd-demo-${var.environment} -f"
}

output "get_grafana_url" {
  description = "Grafana LoadBalancer URL — available after ArgoCD syncs kube-prometheus (may take a few minutes post-apply)"
  value       = "kubectl get svc kube-prometheus-grafana -n monitoring --context argocd-demo-${var.environment} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
