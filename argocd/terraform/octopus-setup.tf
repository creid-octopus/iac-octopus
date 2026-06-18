# octopus-setup.tf
#
# The three demo projects (demo-app-raw, demo-app-kustomize, demo-app-helm) use
# Octopus Config as Code. Their deployment processes, variables, and step
# configuration live as OCL files in each project's associated git repo — not
# here.
#
# Nothing is actively managed in this file right now. It's a placeholder for
# any project-level infra (channels, triggers, tenants) that might need wiring
# via Terraform later.
#
# Not managed here:
#   Docker Hub external feed  — pre-existing in the space
#   GitHub git credential     — Library → Git Credentials (UI)
#   Project variables         — each project's .octopus/variables.ocl (CaC)
#   Deployment process steps  — each project's .octopus/deployment_process.ocl (CaC)
#
# Reference material for the CaC config:
#   argocd/octopus/scripts/promote.sh   script body for the Commit to Git step
#   argocd/octopus/steps/               YAML templates for Deploy Kubernetes YAML steps
#   argocd/octopus/SETUP.md             step-by-step setup guide
