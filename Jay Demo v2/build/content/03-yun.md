# 3. Yun's architecture, box by box {#s3}

Yun's diagram is the target. The demo walks its middle path: an agent calls APIM (③), APIM calls Databricks as a managed identity (④), Unity Catalog decides the data, and Databricks calls a Foundry model back through APIM (⑤).

@img 01-yun-architecture.png | Image 1. Yun's target architecture for IMH, boxes ① to ⑥

{widths: 1100 2600 4060 1600}
| Yun | Box | What we show | Status |
|---|---|---|---|
| ① | Teams / M365 Copilot / Copilot Studio (Entra sign-in) | Not built | Talk track |
| ② | Cloudflare → App Gateway (WAF) | Not built (networking) | Talk track |
| Runtime | Agent runtime: AKS | Container Apps job `job-imh-uc-agent` with its own managed identity (step 10) | Stand-in |
| Runtime | Foundry Agent Service | Agents C and H (steps 6–7) | Live |
| ③ | APIM validates the Entra token, applies policy, routes to the MCP tool | `/uc-entra` (token + allowed-app list, 401 otherwise); `/uc` and `/uc-limited` (key + limits) | Live (interim audience) |
| ④ | APIM → Databricks managed MCP / UC, OAuth M2M via Entra | APIM signs in as `umi-imh-uc-agent`, a service principal in `imh_analyst` | Identity live; private network not built |
| UC | Unity Catalog governs access | Row filter + masks on `imh_demo.clinical.patients` | Live |
| ⑤ | Databricks → Unity AI Gateway → APIM → Foundry models | Endpoint `imh-foundry-gpt41-via-apim` → APIM `/aoai` → gpt-4.1 (step 11) | Live |
| ⑥ | AKS / APIM → Foundry models over private endpoint | `/aoai` over the public network | Public here |
| Open item | APIM ↔ Databricks serverless connectivity (DMZ) | Identity proven; network not built (Private Link one way, NCC the other) | Talk track |
| Open item | Result-size / row limits via APIM MCP | `/uc-limited` (step 7) | Live |
| Open item | AKS as the standard runtime | Same client in Container Apps; on AKS only the sign-in changes (workload identity) | Stand-in |
| Open item | Foundry public DNS limitation → runtime on AKS | Both runtimes call the same governed APIM tool | Live |

@img 02-yun-open-items.png | Image 2. Yun's open items

## Where the two priorities land
- **Priority 1, Microsoft agents → Databricks tools:** the middle path, Runtime → ③ → ④ → Unity Catalog. Steps 3–10.
- **Priority 2, Databricks agents ↔ Microsoft services:** ⑤ (Databricks → APIM → Foundry model, step 11) and Genie One → Microsoft 365 (step 12). The entry at ①, Copilot Studio or Teams calling Databricks, is not built.
- **What to say about ⑥ and the open items:** identity and policy are proven; the private network is the IMH build (Private Link from APIM to Databricks, NCC from Databricks serverless back to APIM).
