#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 04-workload-identity-federation.sh
# Keyless authentication for an on-premises application calling Vertex AI:
# the application presents a token from the client's own identity provider
# (AD FS, Entra ID, Ping or Okta - any OIDC issuer), Security Token Service
# exchanges it, and the app impersonates the invoker service account created by
# 02-configure-vertex-access.sh. No service account keys are created.
#
# Usage:
#   PROJECT_ID=ai-fedramp-prod ISSUER_URI=https://sts.agency.example/adfs \
#   AUDIENCE=api://vertex-onprem SUBJECT=onprem-claims-app \
#   TOKEN_FILE=/var/run/secrets/idp/token APPLY=true ./04-workload-identity-federation.sh
#
# Output: onprem-wif-config.json - a credential configuration (no secrets) that
# the application loads through GOOGLE_APPLICATION_CREDENTIALS.
# With VPC Service Controls, allow sts.googleapis.com and iamcredentials.googleapis.com
# for this identity in the perimeter ingress policy.
# Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
# -----------------------------------------------------------------------------
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${ISSUER_URI:?Set ISSUER_URI (OIDC issuer of the on-prem identity provider)}"
: "${AUDIENCE:?Set AUDIENCE (audience the IdP puts in the token)}"
: "${SUBJECT:?Set SUBJECT (sub claim of the on-prem application identity)}"
: "${TOKEN_FILE:?Set TOKEN_FILE (path where the app writes its current IdP token)}"
POOL_ID="${POOL_ID:-onprem-pool}"
PROVIDER_ID="${PROVIDER_ID:-onprem-oidc}"
SA_EMAIL="${SA_EMAIL:-vertex-invoker@${PROJECT_ID}.iam.gserviceaccount.com}"
APPLY="${APPLY:-false}"

run() { if [[ "$APPLY" == "true" ]]; then echo "+ $*"; "$@"; else echo "[plan] $*"; fi; }

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}"

run gcloud services enable iam.googleapis.com sts.googleapis.com iamcredentials.googleapis.com --project="$PROJECT_ID"

if ! gcloud iam workload-identity-pools describe "$POOL_ID" --project="$PROJECT_ID" --location=global >/dev/null 2>&1; then
  run gcloud iam workload-identity-pools create "$POOL_ID" --project="$PROJECT_ID" --location=global \
    --display-name="On-prem workloads" --description="On-premises applications calling Vertex AI"
fi

if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" --project="$PROJECT_ID" \
     --location=global --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  run gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" --location=global --workload-identity-pool="$POOL_ID" \
    --issuer-uri="$ISSUER_URI" --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub" \
    --attribute-condition="assertion.sub == '${SUBJECT}'"
fi

# Only this one external subject may impersonate the invoker service account
run gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" --project="$PROJECT_ID" \
  --role=roles/iam.workloadIdentityUser \
  --member="principal://iam.googleapis.com/${POOL}/subject/${SUBJECT}"

run gcloud iam workload-identity-pools create-cred-config "${POOL}/providers/${PROVIDER_ID}" \
  --service-account="$SA_EMAIL" --credential-source-file="$TOKEN_FILE" \
  --output-file=onprem-wif-config.json

echo
echo "Copy onprem-wif-config.json to the application host and set:"
echo "  export GOOGLE_APPLICATION_CREDENTIALS=/etc/vertex/onprem-wif-config.json"
echo "Then test with client/onprem_vertex_client.py."
