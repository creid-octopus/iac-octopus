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
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --context argocd-demo-${var.environment}"
}

output "argocd_server_ip" {
  description = "ArgoCD LoadBalancer IP — computed during apply"
  value       = local.argocd_external_ip
}

output "argocd_login_command" {
  description = "ArgoCD CLI login command — fill in the IP from get_argocd_ip"
  value       = "argocd login <EXTERNAL-IP> --username admin --insecure"
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
