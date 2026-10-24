#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-validate-foundation.sh
# Read-only validation of the Google Cloud foundation for a FedRAMP High
# Vertex AI (Gemini Enterprise Agent Platform) workload:
#   organization, Assured Workloads folder and control package, project
#   placement, billing, resource locations, restricted services, Vertex AI
#   API, model allow-list, grounding, service account keys, data caching.
#
# Usage:
#   ORG_ID=123456789012 PROJECT_ID=ai-fedramp-prod WORKLOAD_ID=<id> ./01-validate-foundation.sh
#
# Optional: AW_LOCATION (default us), REGION (default us-central1)
# Requires: gcloud, curl, jq. Caller needs read access to the org, the
# Assured Workloads resource, the project and its billing info.
# Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
# -----------------------------------------------------------------------------
set -uo pipefail

: "${ORG_ID:?Set ORG_ID}"
: "${PROJECT_ID:?Set PROJECT_ID}"
: "${WORKLOAD_ID:?Set WORKLOAD_ID (gcloud assured workloads list --organization=\$ORG_ID --location=us)}"
AW_LOCATION="${AW_LOCATION:-us}"
REGION="${REGION:-us-central1}"

PASS=0; FAIL=0; WARN=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARN=$((WARN + 1)); }
section() { printf '\n== %s\n' "$1"; }

effective_policy() {  # $1 = constraint (without constraints/ prefix)
  gcloud org-policies describe "$1" --project="$PROJECT_ID" --effective --format=json 2>/dev/null || echo '{}'
}

section "Organization"
if ORG_NAME=$(gcloud organizations describe "$ORG_ID" --format='value(displayName)' 2>/dev/null); then
  pass "Organization reachable: $ORG_NAME ($ORG_ID)"
else
  fail "Cannot read organization $ORG_ID (check roles/resourcemanager.organizationViewer)"
fi

section "Assured Workloads"
WL_JSON=$(gcloud assured workloads describe "$WORKLOAD_ID" --organization="$ORG_ID" --location="$AW_LOCATION" --format=json 2>/dev/null || echo '{}')
REGIME=$(jq -r '.complianceRegime // empty' <<<"$WL_JSON")
FOLDER_ID=$(jq -r '[.resources[]? | select(.resourceType == "CONSUMER_FOLDER") | .resourceId][0] // empty' <<<"$WL_JSON")
case "$REGIME" in
  FEDRAMP_HIGH)     pass "Control package: FedRAMP High (folder $FOLDER_ID)" ;;
  FEDRAMP_MODERATE) warn "Control package is FedRAMP Moderate - confirm the authorization level the client requires" ;;
  "")               fail "Workload $WORKLOAD_ID not found in $AW_LOCATION" ;;
  *)                warn "Control package is $REGIME" ;;
esac

VIOLATIONS=$(gcloud assured workloads violations list --organization="$ORG_ID" --location="$AW_LOCATION" \
  --workload="$WORKLOAD_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$VIOLATIONS" == "0" ]]; then pass "No open Assured Workloads violations"; else warn "$VIOLATIONS Assured Workloads violation(s) - review before configuring"; fi

section "Project placement and billing"
PARENT=$(gcloud projects describe "$PROJECT_ID" --format='value(parent.type,parent.id)' 2>/dev/null | tr '\t' '/')
if [[ -n "$FOLDER_ID" && "$PARENT" == "folder/$FOLDER_ID" ]]; then
  pass "Project $PROJECT_ID is inside the Assured Workloads folder"
else
  fail "Project parent is '$PARENT', expected folder/$FOLDER_ID - move or recreate the project inside the folder"
fi
BILLING=$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled,billingAccountName)' 2>/dev/null)
if [[ "$BILLING" == True* ]]; then pass "Billing enabled ($(cut -f2 <<<"$BILLING"))"; else fail "Billing not enabled or not readable"; fi

section "Locations and services"
LOC=$(effective_policy gcp.resourceLocations)
ALLOWED_LOC=$(jq -r '[.spec.rules[]?.values.allowedValues[]?] | join(",")' <<<"$LOC")
if [[ "$ALLOWED_LOC" =~ us ]] && ! [[ "$ALLOWED_LOC" =~ (eu|asia|europe|australia|northamerica-northeast) ]]; then
  pass "Resource locations restricted to US: $ALLOWED_LOC"
else
  fail "Resource locations not restricted to US (effective: ${ALLOWED_LOC:-none})"
fi
SVC=$(effective_policy gcp.restrictServiceUsage)
if jq -e '[.spec.rules[]?.values.allowedValues[]?] | index("aiplatform.googleapis.com")' <<<"$SVC" >/dev/null; then
  pass "aiplatform.googleapis.com is allowed by gcp.restrictServiceUsage"
else
  warn "aiplatform.googleapis.com not listed in gcp.restrictServiceUsage allow-list (or policy not set)"
fi
if gcloud services list --enabled --project="$PROJECT_ID" --filter='config.name=aiplatform.googleapis.com' --format='value(config.name)' 2>/dev/null | grep -q aiplatform; then
  pass "Vertex AI API enabled"
else
  warn "Vertex AI API not enabled yet (02-configure-vertex-access.sh)"
fi

section "Model access and grounding"
MODELS=$(effective_policy vertexai.allowedModels)
COUNT=$(jq '[.spec.rules[]?.values.allowedValues[]?] | length' <<<"$MODELS")
if [[ "$COUNT" -gt 0 ]]; then pass "Model allow-list set ($COUNT model actions)"; else fail "vertexai.allowedModels not set - every Model Garden model is allowed"; fi
GROUND=$(effective_policy vertexai.disableGenAIGoogleSearchGrounding)
if jq -e '[.spec.rules[]?.enforce] | index(true)' <<<"$GROUND" >/dev/null; then pass "Grounding with Google Search disabled"; else fail "Grounding with Google Search not disabled"; fi

section "Identity"
KEYS=$(effective_policy iam.disableServiceAccountKeyCreation)
if jq -e '[.spec.rules[]?.enforce] | index(true)' <<<"$KEYS" >/dev/null; then pass "Service account key creation disabled"; else fail "Service account key creation is allowed"; fi
USER_KEYS=0
for sa in $(gcloud iam service-accounts list --project="$PROJECT_ID" --format='value(email)' 2>/dev/null); do
  n=$(gcloud iam service-accounts keys list --iam-account="$sa" --managed-by=user --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')
  USER_KEYS=$((USER_KEYS + n))
done
if [[ "$USER_KEYS" == "0" ]]; then pass "No user-managed service account keys"; else fail "$USER_KEYS user-managed service account key(s) present - replace with Workload Identity Federation"; fi

section "Zero data retention"
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
CACHE=$(curl -sS -H "Authorization: Bearer $TOKEN" \
  "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/cacheConfig" 2>/dev/null || echo '{}')
if [[ "$(jq -r '.disableCache // false' <<<"$CACHE")" == "true" ]]; then
  pass "Implicit data caching disabled"
else
  fail "Implicit data caching enabled (default) - run 03-zero-data-retention.sh"
fi

printf '\nSummary: %s passed, %s warnings, %s failed\n' "$PASS" "$WARN" "$FAIL"
[[ "$FAIL" -eq 0 ]]
