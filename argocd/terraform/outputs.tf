output "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "AKS cluster name — use with 'az aks get-credentials'"
  value       = azurerm_kubernetes_cluster.main.name
}

output "kube_config_raw" {
  description = "Raw kubeconfig — use 'az aks get-credentials' instead for local use"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "get_credentials_command" {
  description = "Run this after apply to configure kubectl and Headlamp"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --context argocd-demo"
}

output "get_argocd_ip" {
  description = "Run after apply to get the ArgoCD LoadBalancer IP (may take ~60s after apply for Azure to assign)"
  value       = "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --context argocd-demo"
}

output "argocd_login_command" {
  description = "ArgoCD CLI login command — fill in the IP from get_argocd_ip"
  value       = "argocd login <EXTERNAL-IP> --username admin --insecure"
}
