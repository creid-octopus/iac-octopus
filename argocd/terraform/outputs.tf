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
  description = "Octopus deployment target ID for the primary Kubernetes agent (c01)"
  value       = octopusdeploy_kubernetes_agent_deployment_target.k8s_agent.id
}

output "k8s_agent_target_ids" {
  description = "Map of cluster IDs to Octopus deployment target IDs"
  value       = {
    c02 = octopusdeploy_kubernetes_agent_deployment_target.extra_agent["c02"].id
    c03 = octopusdeploy_kubernetes_agent_deployment_target.extra_agent["c03"].id
  }
}

output "k8s_agent_names" {
  description = "Map of cluster IDs to Octopus agent target names"
  value       = {
    c02 = helm_release.extra_agent_c02.name
    c03 = helm_release.extra_agent_c03.name
  }
}

output "get_k8s_agent_logs" {
  description = "Tail Kubernetes agent logs to verify Octopus connection"
  value       = "kubectl logs -l app.kubernetes.io/name=kubernetes-agent -n ${var.kubernetes_agent_namespace} --context argocd-demo-${var.environment} -f"
}

output "get_extra_k8s_agent_logs" {
  description = "Tail Kubernetes agent logs for extra clusters. Use 'az aks get-credentials' with the cluster name, then: kubectl logs -l app.kubernetes.io/name=kubernetes-agent -n octopus-k8s-agent --context=<cluster-name> -f"
  value       = "az aks get-credentials -g creid-rg-meta-nonprod -n <cluster-name>; kubectl logs -l app.kubernetes.io/name=kubernetes-agent -n octopus-k8s-agent -f"
}

output "get_grafana_ip" {
  description = "Grafana LoadBalancer IP — available after ArgoCD syncs kube-prometheus (may take a few minutes post-apply)"
  value       = "kubectl get svc kube-prometheus-grafana -n monitoring --context argocd-demo-${var.environment} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
