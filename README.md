# Vertex AI FedRAMP Command Center

**Live dashboard:** https://kennyb7322.github.io/vertex-ai-fedramp-command-center/

A reference configuration and live-session runbook for **Gemini models on Vertex AI (now Gemini Enterprise Agent Platform) inside a Google Cloud Assured Workloads FedRAMP High boundary**, called by an **on-premises application**. It covers what a short, hands-on engagement has to get right: organization, project and billing validation; the Assured Workloads control package; FedRAMP-aligned regions and data residency; model enablement and allow-listing; keyless API authentication; zero data retention; and the private network path from on-prem.

> Environment values are **illustrative**; no client data is used. Commands, org-policy constraints and API resources follow Google Cloud documentation as of October 2026. Confirm model availability, package features and pricing for your organization before relying on them.

## What's inside

| Section | What it demonstrates |
|---|---|
| Session readiness | 44 validation checks by domain, before and after the session |
| Role requirements coverage | Every responsibility, required and preferred item mapped to a section |
| 1–2 day session plan | Validate → Configure → Integrate → Prove → Document, with prerequisites |
| Org, project & billing | Resource hierarchy under the Assured Workloads folder and validation commands |
| Assured Workloads | FedRAMP Moderate / High / IL4 / CJIS packages, folder guardrails, violation monitoring |
| FedRAMP regions & residency | US-only resource locations, regional (not global) Vertex AI endpoints |
| Model enablement & access | `constraints/vertexai.allowedModels`, Google Search grounding off, single-permission invoker role |
| API authentication | Workload Identity Federation vs. impersonation vs. service account keys vs. API keys |
| Zero data retention | Implicit caching (`cacheConfig`), grounding, request-response logging, Interactions API `store`, session resumption, agents, abuse monitoring |
| On-prem integration | Interconnect / HA VPN → Private Service Connect → VPC Service Controls → regional API; client code; troubleshooting matrix |
| Perimeter, keys & audit | VPC-SC, CMEK, Data Access audit logs, Access Transparency — mapped to NIST 800-53 |
| Live session runbook | 17 steps with commands and verification; tick-off progress saved in the browser |

## Code

| File | Purpose | Changes anything? |
|---|---|---|
| [`scripts/01-validate-foundation.sh`](scripts/01-validate-foundation.sh) | Read-only PASS / WARN / FAIL validation of org, Assured Workloads, project, billing, locations, model policy, identity and caching | No |
| [`scripts/02-configure-vertex-access.sh`](scripts/02-configure-vertex-access.sh) | Enable Vertex AI; model allow-list; grounding off; no SA keys; invoker service account with a custom role holding only `aiplatform.endpoints.predict` | Only with `APPLY=true` |
| [`scripts/03-zero-data-retention.sh`](scripts/03-zero-data-retention.sh) | Disable and verify implicit data caching; disable Maps grounding; list the remaining ZDR controls | Only with `APPLY=true` |
| [`scripts/04-workload-identity-federation.sh`](scripts/04-workload-identity-federation.sh) | OIDC pool and provider for the on-prem IdP, impersonation binding, credential config (no keys) | Only with `APPLY=true` |
| [`client/onprem_vertex_client.py`](client/onprem_vertex_client.py) | Keyless `generateContent` call over a regional or PSC endpoint, with retries | — |
| [`terraform/assured-workload`](terraform/assured-workload) | FedRAMP High workload, project in the folder, APIs, folder guardrail policies (`terraform validate` clean) | `terraform apply` |

Shell scripts pass `bash -n` and ShellCheck; the Python client compiles; the Terraform module validates against the Google provider.

## Run the dashboard

`index.html` is a single self-contained file (Chart.js and Google Fonts from CDN). Open it in a browser or serve the folder:

```bash
python3 -m http.server 8080
```

## Author

**Kenneth P. Barnes** — Founder, CTO & CISO, Ultimate Computer Solutions, Inc. (UCS Solutions, est. 1993) · US Citizen
KBarnes@ucsolutions.com · [linkedin.com/in/drkennethpbarnes](https://www.linkedin.com/in/drkennethpbarnes) · [github.com/kennyb7322](https://github.com/kennyb7322)
