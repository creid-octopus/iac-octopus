# iac-octopus

Infrastructure as code and configuration for Octopus Deploy demo environments.

## Contents

| Directory | Description |
|-----------|-------------|
| `argocd/` | AKS cluster with ArgoCD, Octopus gateway integration, and GitOps demo applications |
| `terraform/` | (Reserved for future shared infrastructure) |

## Quick start

See [`argocd/README.md`](argocd/README.md) for the ArgoCD demo environment — setup, teardown, and recreation instructions.

## Prerequisites

- Azure CLI (`az login` to the demo subscription)
- Terraform >= 1.5
- kubectl, helm, argocd CLI
- direnv (for `.envrc` credential management)
