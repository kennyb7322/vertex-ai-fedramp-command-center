#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-configure-vertex-access.sh
# Enables Vertex AI in a FedRAMP High Assured Workloads project and applies
# least-privilege model access:
#   - Vertex AI API enabled
#   - Model Garden allow-list (constraints/vertexai.allowedModels) at the folder
#   - Grounding with Google Search disabled at the folder
#   - Service account key creation disabled at the folder
#   - Invoker service account + custom role holding only aiplatform.endpoints.predict
#
# Usage (dry run prints the plan; APPLY=true makes changes):
#   PROJECT_ID=ai-fedramp-prod FOLDER_ID=123456789 \
#   ALLOWED_MODELS="gemini-2.5-pro gemini-2.5-flash" APPLY=true ./02-configure-vertex-access.sh
#
# Model ids must exactly match the versions you call (an entry for a model id
# does not cover a pinned version suffix). Confirm each model is available in
# the Assured Workloads location before adding it.
# Caller needs: Organization Policy Administrator on the folder, Service Usage
# Admin, Service Account Admin, Role Administrator and Project IAM Admin on the project.
# Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
# -----------------------------------------------------------------------------
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${FOLDER_ID:?Set FOLDER_ID (the Assured Workloads folder)}"
ALLOWED_MODELS="${ALLOWED_MODELS:-gemini-2.5-pro gemini-2.5-flash}"
SA_NAME="${SA_NAME:-vertex-invoker}"
ROLE_ID="${ROLE_ID:-vertexGeminiInvoker}"
APPLY="${APPLY:-false}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

run() { if [[ "$APPLY" == "true" ]]; then echo "+ $*"; "$@"; else echo "[plan] $*"; fi; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# 1. API
run gcloud services enable aiplatform.googleapis.com --project="$PROJECT_ID"

# 2. Model allow-list at the folder (everything not listed is denied)
{
  echo "name: folders/${FOLDER_ID}/policies/vertexai.allowedModels"
  echo "spec:"
  echo "  rules:"
  echo "  - values:"
  echo "      allowedValues:"
  for m in $ALLOWED_MODELS; do echo "      - publishers/google/models/${m}:predict"; done
} > "$WORK/allowed-models.yaml"
echo "--- allowed-models.yaml"; cat "$WORK/allowed-models.yaml"
run gcloud org-policies set-policy "$WORK/allowed-models.yaml"

# 3. Boolean guardrails at the folder
for c in vertexai.disableGenAIGoogleSearchGrounding iam.disableServiceAccountKeyCreation; do
  printf 'name: folders/%s/policies/%s\nspec:\n  rules:\n  - enforce: true\n' "$FOLDER_ID" "$c" > "$WORK/$c.yaml"
  run gcloud org-policies set-policy "$WORK/$c.yaml"
done

# 4. Invoker identity with a single permission
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  run gcloud iam service-accounts create "$SA_NAME" --project="$PROJECT_ID" \
    --display-name="Vertex AI invoker (on-prem application)"
fi
if ! gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  run gcloud iam roles create "$ROLE_ID" --project="$PROJECT_ID" --title="Vertex Gemini Invoker" \
    --description="Call approved Gemini models only" --permissions=aiplatform.endpoints.predict --stage=GA
fi
run gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" --role="projects/${PROJECT_ID}/roles/${ROLE_ID}" --condition=None

echo
echo "Next: 03-zero-data-retention.sh, then 04-workload-identity-federation.sh for the on-prem caller."
