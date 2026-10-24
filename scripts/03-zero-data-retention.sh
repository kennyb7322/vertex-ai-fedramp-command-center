#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 03-zero-data-retention.sh
# Applies and verifies the project-level controls for zero data retention with
# Gemini models on Vertex AI (Gemini Enterprise Agent Platform):
#   - Implicit data caching (in-memory and durable, up to 24 hours) disabled
#     through the project cacheConfig resource
#   - Grounding with Google Maps API disabled (Maps grounding retains data 30 days)
# and prints the controls that are enforced in application code or by contract.
#
# Usage:  PROJECT_ID=ai-fedramp-prod ./03-zero-data-retention.sh            # report only
#         PROJECT_ID=ai-fedramp-prod APPLY=true ./03-zero-data-retention.sh # apply + verify
# Requires roles/aiplatform.admin to change cacheConfig (viewer to read it).
# Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
# -----------------------------------------------------------------------------
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
REGION="${REGION:-us-central1}"
APPLY="${APPLY:-false}"
URL="https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/cacheConfig"
TOKEN=$(gcloud auth print-access-token)

echo "== Current cacheConfig"
curl -sS -H "Authorization: Bearer ${TOKEN}" "$URL"; echo

if [[ "$APPLY" == "true" ]]; then
  echo "== Disabling implicit caching (applies to all regions for the project)"
  curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" "$URL" \
    -d "{\"name\": \"projects/${PROJECT_ID}/cacheConfig\", \"disableCache\": true}"; echo

  echo "== Disabling Grounding with Google Maps API if enabled"
  if gcloud services list --enabled --project="$PROJECT_ID" --filter='config.name=mapsgrounding.googleapis.com' \
       --format='value(config.name)' | grep -q mapsgrounding; then
    gcloud services disable mapsgrounding.googleapis.com --project="$PROJECT_ID"
  else
    echo "   not enabled"
  fi
fi

echo "== Verification"
STATE=$(curl -sS -H "Authorization: Bearer ${TOKEN}" "$URL")
if [[ "$(jq -r '.disableCache // false' <<<"$STATE")" == "true" ]]; then
  echo "   PASS  caching disabled"
else
  echo "   FAIL  caching still enabled: $STATE"
fi

cat <<'EOF'

== Controls enforced outside this script (record each in the as-built evidence)
  - Grounding with Google Search: org policy vertexai.disableGenAIGoogleSearchGrounding = true
    (search query logs are retained up to 3 days and cannot be disabled)
  - Request-response logging to BigQuery: off by default - confirm it was never enabled per model
  - Interactions API: send store=false on every request (the default is true)
  - Gemini Live API session resumption: do not request it (cached up to 24 hours when used)
  - Deep Research agent, agent sandbox snapshots and CodeMender retain session data - keep out of scope
  - Abuse-monitoring prompt logging: governed by the Cloud terms and, for advanced models or
    features, the Advanced AI Safety Addendum - confirm the client's position with the Google account team
  - Training: Google does not use customer data to train models without permission
EOF
