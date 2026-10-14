# 11. Not built, and BrakeKat vs IMH {#s11}

Say these before anyone asks. Step 13 covers the first three.

- ① Copilot Studio / Teams → Databricks, and ② Cloudflare → App Gateway (WAF): talk track only.
- Private network: Private Link (APIM → Databricks), NCC (Databricks serverless → APIM), VNet peering, West US 2 + East US 2.
- AKS: a Container Apps job stands in, because the AKS provider isn't registered in BrakeKat. On AKS it's the same code with workload identity.
- Gateway app registration: the interim Entra audience is ARM (`https://management.azure.com`) plus the allowed-client list. IMH would use `api://imh-uc-gateway`.
- APIM → Unity Gateway MCP URL: untested. The legacy MCP endpoints are proven.
- Work IQ; Microsoft Learn MCP; a custom Databricks agent on the `/aoai` endpoint.
- `terraform validate` not run.

{widths: 2200 3300 3860}
| Item | BrakeKat demo | IMH |
|---|---|---|
| Tenant and data | Joey's demo tenant, 12 synthetic rows | IMH tenant, real data |
| Runtime | Container Apps job | AKS + workload identity |
| Entra audience | ARM + allowed-app list | `api://imh-uc-gateway` |
| Network | Public | Private Link + APIM VNet integration |
| Front door | None | Cloudflare → App Gateway (WAF) → internal APIM |
| Regions | West US 3 | West US 2 + East US 2, peered |
| APIM → Databricks MCP | Working | `apim-ih-ent-eap-dev` has Databricks REST only; MCP is in cyber review (Yun, Oct 14) |

## Caveats to say up front
- **One tenant here, by necessity.** Foundry's per-user passthrough needs the user in the Foundry project's Entra tenant, so Foundry and Databricks both sit in BrakeKat. IMH would run both in its own tenant, which is the real single-tenant setup.
- **Public network only.** A fully private MCP path is still unproven and is a joint test for the onsite breakout.
- **Agent identity, not caregiver identity.** Option 2 runs as APIM's managed identity (Yun ④). Per-user sign-in (segments A, B and K) was proven Oct 12–14 and removed from Foundry for the onsite; the evidence is in `Jay DEMO\evidence\brakekat-uc-proof\README.md`.
- **Legacy MCP endpoint.** APIM calls `/api/2.0/mcp/functions/imh_demo/clinical`, which bypasses Unity Gateway. For a new build, point APIM at the Unity Gateway URL so both gateways apply.
