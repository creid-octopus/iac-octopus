# octopus-setup.tf — Octopus Deploy projects and feeds for the demo pipelines
#
# Creates:
#   - Docker Hub external feed (for kostiscodefresh/gitops-simple-app image tags)
#   - Three demo projects: demo-app-raw, demo-app-kustomize, demo-app-helm
#   - Project-level variables for each: Image.Tag, Deploy.Approach
#   - Sensitive project variables: GitHub.PAT, GitHub.User, GitHub.Repo, GitHub.Branch
#
# Deployment process steps are configured in the Octopus UI using the templates
# in argocd/octopus/steps/ and the promotion script in argocd/octopus/scripts/.
#
# Variables supplied via TF_VAR_* in .envrc (never committed):
#   TF_VAR_github_pat
#   TF_VAR_github_user
#   TF_VAR_github_repo

# ── Input variables ─────────────────────────────────────────────────────────────
# Note: GitHub credentials for the Commit to Git step are managed as
# Library → Git Credentials in Octopus (not as Terraform-managed variables).
# No github_pat variable is needed here — configure the credential in the UI
# and reference it by name in the step configuration.

# ── Data: lifecycle and project group ───────────────────────────────────────────
# These must already exist in the Octopus space (they're not created here).

data "octopusdeploy_lifecycles" "default" {
  space_id = var.octopus_space_id
  skip     = 0
  take     = 1
}

data "octopusdeploy_project_groups" "default" {
  space_id = var.octopus_space_id
  skip     = 0
  take     = 1
}

# ── Docker Hub feed ─────────────────────────────────────────────────────────────

resource "octopusdeploy_docker_container_registry" "docker_hub" {
  name     = "Docker Hub"
  space_id = var.octopus_space_id
  api_url  = "https://index.docker.io"

  lifecycle {
    # Ignore if a Docker Hub feed already exists (common in shared spaces)
    ignore_changes = [name]
  }
}

# ── Helper local: shared project settings ───────────────────────────────────────

locals {
  demo_projects = {
    raw        = { name = "demo-app-raw",        approach = "raw" }
    kustomize  = { name = "demo-app-kustomize",   approach = "kustomize-dev" }
    helm       = { name = "demo-app-helm",        approach = "helm" }
  }
}

# ── Projects ────────────────────────────────────────────────────────────────────

resource "octopusdeploy_project" "demo_app_raw" {
  name             = "demo-app-raw"
  description      = "GitOps demo — Raw YAML approach. Two deploy modes: git-update (promote.sh) and direct K8s agent."
  space_id         = var.octopus_space_id
  lifecycle_id     = data.octopusdeploy_lifecycles.default.lifecycles[0].id
  project_group_id = data.octopusdeploy_project_groups.default.project_groups[0].id

  connectivity_policy {
    allow_deployments_to_no_targets = false
  }
}

resource "octopusdeploy_project" "demo_app_kustomize" {
  name             = "demo-app-kustomize"
  description      = "GitOps demo — Kustomize approach. Promotes image tag in overlays/dev/kustomization.yaml newTag field."
  space_id         = var.octopus_space_id
  lifecycle_id     = data.octopusdeploy_lifecycles.default.lifecycles[0].id
  project_group_id = data.octopusdeploy_project_groups.default.project_groups[0].id

  connectivity_policy {
    allow_deployments_to_no_targets = false
  }
}

resource "octopusdeploy_project" "demo_app_helm" {
  name             = "demo-app-helm"
  description      = "GitOps demo — Helm approach. Promotes image tag in environments/helm/values.yaml."
  space_id         = var.octopus_space_id
  lifecycle_id     = data.octopusdeploy_lifecycles.default.lifecycles[0].id
  project_group_id = data.octopusdeploy_project_groups.default.project_groups[0].id

  connectivity_policy {
    allow_deployments_to_no_targets = false
  }
}

# ── Project variables ────────────────────────────────────────────────────────────
# GitHub credentials are NOT managed here — use Library → Git Credentials in
# Octopus and reference the credential in the Commit to Git step directly.

resource "octopusdeploy_variable" "raw_image_tag" {
  name       = "Image.Tag"
  type       = "String"
  value      = "v2.0"
  project_id = octopusdeploy_project.demo_app_raw.id
  space_id   = var.octopus_space_id
}

resource "octopusdeploy_variable" "raw_deploy_approach" {
  name       = "Deploy.Approach"
  type       = "String"
  value      = "raw"
  project_id = octopusdeploy_project.demo_app_raw.id
  space_id   = var.octopus_space_id
}

resource "octopusdeploy_variable" "kustomize_image_tag" {
  name       = "Image.Tag"
  type       = "String"
  value      = "v2.0"
  project_id = octopusdeploy_project.demo_app_kustomize.id
  space_id   = var.octopus_space_id
}

resource "octopusdeploy_variable" "kustomize_deploy_approach" {
  name       = "Deploy.Approach"
  type       = "String"
  value      = "kustomize-dev"
  project_id = octopusdeploy_project.demo_app_kustomize.id
  space_id   = var.octopus_space_id
}

resource "octopusdeploy_variable" "helm_image_tag" {
  name       = "Image.Tag"
  type       = "String"
  value      = "v2.0"
  project_id = octopusdeploy_project.demo_app_helm.id
  space_id   = var.octopus_space_id
}

resource "octopusdeploy_variable" "helm_deploy_approach" {
  name       = "Deploy.Approach"
  type       = "String"
  value      = "helm"
  project_id = octopusdeploy_project.demo_app_helm.id
  space_id   = var.octopus_space_id
}

# ── Outputs ──────────────────────────────────────────────────────────────────────

output "docker_hub_feed_id" {
  description = "Octopus Docker Hub feed ID — use when creating releases against the kostiscodefresh/gitops-simple-app image"
  value       = octopusdeploy_docker_container_registry.docker_hub.id
}

output "demo_project_ids" {
  description = "Octopus project IDs for the three demo projects"
  value = {
    raw       = octopusdeploy_project.demo_app_raw.id
    kustomize = octopusdeploy_project.demo_app_kustomize.id
    helm      = octopusdeploy_project.demo_app_helm.id
  }
}
