"""
onprem_vertex_client.py

Calls an approved Gemini model on Vertex AI (Gemini Enterprise Agent Platform)
from an on-premises application:

  * keyless credentials - Workload Identity Federation configuration from
    04-workload-identity-federation.sh, loaded via GOOGLE_APPLICATION_CREDENTIALS
  * regional endpoint inside the US data boundary (never the global endpoint),
    or a Private Service Connect endpoint reached over Interconnect / HA VPN
  * corporate proxy honored through HTTPS_PROXY
  * bounded retries with exponential backoff on 429 / 5xx

Environment:
  PROJECT_ID   Google Cloud project inside the Assured Workloads folder (required)
  REGION       e.g. us-central1 (default)
  MODEL        model id on the org-policy allow-list, e.g. gemini-2.5-flash
  API_HOST     override host, e.g. us-central1-aiplatform-vertexpsc.p.googleapis.com

Usage:
  pip install google-auth requests
  python onprem_vertex_client.py "Summarize the attached case note in three bullets."

Author: Kenneth P. Barnes - github.com/kennyb7322/vertex-ai-fedramp-command-center
"""
from __future__ import annotations

import os
import random
import sys
import time

import google.auth
from google.auth.transport.requests import AuthorizedSession

PROJECT_ID = os.environ.get("PROJECT_ID", "")
REGION = os.environ.get("REGION", "us-central1")
MODEL = os.environ.get("MODEL", "gemini-2.5-flash")
API_HOST = os.environ.get("API_HOST", f"{REGION}-aiplatform.googleapis.com")
SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]
RETRYABLE = {429, 500, 502, 503, 504}


def build_session() -> AuthorizedSession:
    """Credentials come from GOOGLE_APPLICATION_CREDENTIALS (an external_account config)."""
    credentials, _ = google.auth.default(scopes=SCOPES)
    return AuthorizedSession(credentials)


def generate(session: AuthorizedSession, prompt: str, max_attempts: int = 5) -> str:
    if not PROJECT_ID:
        raise SystemExit("Set PROJECT_ID")
    if REGION == "global" or API_HOST.startswith("aiplatform.googleapis.com"):
        raise SystemExit("Use a regional or PSC endpoint inside the data boundary, not the global endpoint")

    url = (
        f"https://{API_HOST}/v1/projects/{PROJECT_ID}/locations/{REGION}"
        f"/publishers/google/models/{MODEL}:generateContent"
    )
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1024},
    }

    for attempt in range(1, max_attempts + 1):
        response = session.post(url, json=body, timeout=60)
        if response.status_code == 200:
            data = response.json()
            parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            return "".join(p.get("text", "") for p in parts)
        if response.status_code in RETRYABLE and attempt < max_attempts:
            delay = min(30, (2 ** attempt) + random.random())
            print(f"HTTP {response.status_code}; retrying in {delay:.1f}s", file=sys.stderr)
            time.sleep(delay)
            continue
        # 403 usually means: model not on vertexai.allowedModels, missing aiplatform.endpoints.predict,
        # or the request was blocked by the VPC Service Controls perimeter.
        raise RuntimeError(f"HTTP {response.status_code}: {response.text[:500]}")
    raise RuntimeError("retries exhausted")


if __name__ == "__main__":
    text = " ".join(sys.argv[1:]) or "Reply with the single word: connected."
    print(generate(build_session(), text))
