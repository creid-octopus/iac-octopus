#!/usr/bin/env bash
# promote.sh — Image tag promotion script for ArgoCD GitOps
#
# ── TWO USAGE MODES ─────────────────────────────────────────────────────────────
#
# 1. OCTOPUS "COMMIT TO GIT" STEP (preferred)
#    Paste only the section marked [COMMIT TO GIT BODY] into the step's Script
#    field. Octopus clones the repo before the script runs and commits/pushes
#    after it — no git operations needed in the script.
#    Required variables: Image.Tag, Deploy.Approach
#    Credential: set up a Library Git Credential in Octopus; no project variables
#    needed for git auth.
#
# 2. LOCAL TESTING / FALLBACK "RUN A SCRIPT" STEP
#    Run this full script locally (set env vars below) to simulate what Octopus
#    does before creating a release, or use it as the body of a plain "Run a
#    Script" step with GitHub.PAT/GitHub.User/GitHub.Repo/GitHub.Branch as
#    Octopus project variables.
#
# ────────────────────────────────────────────────────────────────────────────────

# ════════════════════════════════════════════════════════════════════════════════
# [COMMIT TO GIT BODY] — paste everything between these markers into the step
# ════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# In a Commit to Git step, Octopus sets Octopus.Calamari.Git.RepositoryPath to
# the cloned repo root. For local testing, set REPO_PATH to the local checkout.
REPO_PATH="${OCTOPUS_CALAMARI_GIT_REPOSITORYPATH:-$(pwd)}"
if command -v get_octopusvariable &>/dev/null; then
  REPO_PATH=$(get_octopusvariable "Octopus.Calamari.Git.RepositoryPath")
fi

IMAGE_TAG="${IMAGE_TAG:-#{Image.Tag}}"
APPROACH="${DEPLOY_APPROACH:-#{Deploy.Approach}}"

echo "==> Approach: ${APPROACH} — setting image tag to ${IMAGE_TAG}"
echo "==> Repo path: ${REPO_PATH}"

case "$APPROACH" in
  raw)
    FILE="$REPO_PATH/argocd/environments/raw/deployment.yaml"
    sed -i "s|kostiscodefresh/gitops-simple-app:.*|kostiscodefresh/gitops-simple-app:${IMAGE_TAG}|g" "$FILE"
    # Anchored on 8-space indentation to avoid matching apiVersion: apps/v1
    sed -i "/^        version: /s|version: .*$|version: ${IMAGE_TAG}|" "$FILE"
    ;;

  kustomize-dev)
    FILE="$REPO_PATH/argocd/environments/kustomize/overlays/dev/kustomization.yaml"
    sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|" "$FILE"
    ;;

  kustomize-staging)
    FILE="$REPO_PATH/argocd/environments/kustomize/overlays/staging/kustomization.yaml"
    sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|" "$FILE"
    ;;

  helm)
    FILE="$REPO_PATH/argocd/environments/helm/values.yaml"
    sed -i "s|^  tag:.*|  tag: ${IMAGE_TAG}|" "$FILE"
    ;;

  *)
    echo "ERROR: Unknown Deploy.Approach '${APPROACH}'." >&2
    echo "       Valid values: raw | kustomize-dev | kustomize-staging | helm" >&2
    exit 1
    ;;
esac

echo "==> Done. Modified: $FILE"

# ════════════════════════════════════════════════════════════════════════════════
# [END COMMIT TO GIT BODY]
# ════════════════════════════════════════════════════════════════════════════════

# ── LOCAL / FALLBACK: commit and push (not needed in Commit to Git step) ────────
# When running locally or in a plain "Run a Script" step, Octopus does not
# handle the commit — do it here instead.

if [[ "${COMMIT_LOCALLY:-false}" == "true" ]]; then
  echo "==> Committing locally..."
  GITHUB_PAT="${GITHUB_PAT:-#{GitHub.PAT}}"
  GITHUB_USER="${GITHUB_USER:-#{GitHub.User}}"
  GITHUB_REPO="${GITHUB_REPO:-#{GitHub.Repo}}"
  GITHUB_BRANCH="${GITHUB_BRANCH:-#{GitHub.Branch}}"

  git -C "$REPO_PATH" config user.email "octopus-deploy@noreply.local"
  git -C "$REPO_PATH" config user.name  "Octopus Deploy"
  git -C "$REPO_PATH" add "$FILE"
  git -C "$REPO_PATH" diff --cached --quiet && {
    echo "==> No change — already at ${IMAGE_TAG}. Nothing to commit."
    exit 0
  }
  git -C "$REPO_PATH" commit -m "deploy(${APPROACH}): promote to ${IMAGE_TAG}"
  git -C "$REPO_PATH" push \
    "https://${GITHUB_USER}:${GITHUB_PAT}@${GITHUB_REPO}" "$GITHUB_BRANCH"
  echo "==> Pushed. ArgoCD will sync automatically."
fi
