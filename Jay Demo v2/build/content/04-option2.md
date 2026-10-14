# 4. Option 2: the slide and what runs {#s4}

@img 03-option2-slide.png | Image 3. IMH's Option 2 slide: Azure agent → APIM → MCP server → UC function → Databricks tables

{widths: 2900 6460}
| On the slide | What runs in the demo |
|---|---|
| Azure Agent | Foundry agents C (`imh-uc-apim-umi-agent` v6) and H (`imh-uc-limited-agent` v3); the Container Apps job `job-imh-uc-agent` as the AKS stand-in |
| APIM | `apim-imh-uc-66zpmtcbvhe7w`, routes `/uc`, `/uc-limited` and `/uc-entra` (plus `/aoai` for the reverse direction) |
| MCP Server | Databricks managed MCP server at `/api/2.0/mcp/functions/imh_demo/clinical` |
| UC Function | `imh_demo.clinical.get_patients(fac)` and `get_patients_limited(fac, max_rows)`. The slide's examples were `get_patient_demographics`, `get_claim_history` and `get_authorization_status` |
| Databricks Tables | `imh_demo.clinical.patients`: 12 synthetic rows with a row filter and two column masks |

## Why Option 2 fits (the slide's "best fit" list)
- **Deterministic workflows:** the agent runs queries we wrote and only fills in parameters.
- **Controlled inputs and outputs:** no free-form SQL; APIM caps rows and size.
- **Reuse across platforms:** Foundry, M365 Copilot and others call the same MCP URL on APIM.
- **Central API policy and monitoring:** APIM policies and logs, plus Databricks Query History.

@img 04-imh-original-sketch-apim-aks-genie.png | Image 4. IMH's original sketch: APIM, AKS and Genie

> NOTE: Genie through APIM (segment G) and per-user Genie One from Foundry (segment K) both worked, but were removed from Foundry on Oct 14 to keep the demo to Option 2. Genie answers open questions; UC functions fit governed, repeatable workflows. Both can sit behind the same APIM.
