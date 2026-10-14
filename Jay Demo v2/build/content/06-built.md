# 6. What was built, and what changed {#s6}

## 6.1 Azure: subscription Azure-brakekat, resource group `rg-ai`, West US 3
{widths: 1900 2860 1500 3100}
| Resource | Name | Type | Role in the demo |
|---|---|---|---|
| API Management | `apim-imh-uc-66zpmtcbvhe7w` | BasicV2 | Microsoft-side gateway: `/uc`, `/uc-limited`, `/uc-entra`, `/aoai` |
| Managed identity | `umi-imh-uc-agent` | User-assigned | APIM → Databricks (service principal in `imh_analyst`) and APIM → Foundry |
| Managed identity | `umi-imh-uc-runtime` | User-assigned | Job → APIM `/uc-entra` (Entra token, no key) |
| Container Apps job | `job-imh-uc-agent` | Manual trigger | AKS stand-in; `APIM_AUTH=mi` |
| Log Analytics | `law-imh-uc-66zpmtcbvhe7w` | Workspace | APIM gateway logs and job console logs |
| Foundry | `aif-wu3` → project `proj-imh-uc-demo` | Foundry resource | gpt-4.1; agents C and H |

{widths: 2400 6960}
| APIM route | How it works |
|---|---|
| `/uc` | API "IMH UC functions MCP (via UMI)". Caller: key, subscription `foundry-imh-uc-agent`<br>Policy: rate limit; managed identity to Databricks `/api/2.0/mcp/functions/imh_demo/clinical` |
| `/uc-limited` | API "IMH UC functions MCP - limited (rate, quota, size cap)". Caller: key, subscription `imh-uc-limited-client`<br>Policy: 3 tool calls a minute, 200 a day; more than 5 rows or 20 KB becomes an MCP error with `x-imh-gateway-block` |
| `/uc-entra` | API "IMH UC functions MCP - Entra token (no key)". Caller: Entra token; only the runtime's app ID is allowed<br>Policy: 401 for anyone else; same backend |
| `/aoai` | API "Foundry models (via UMI)". Caller: key, subscription `databricks-ai-gateway`<br>Policy: `llm-token-limit` 20,000 tokens a minute; managed identity to Foundry `aif-wu3` gpt-4.1 |
| `/genie` | API "IMH Genie space MCP (via UMI)". Left in place from segment G; not shown on Oct 15 |

{widths: 2300 900 3000 3160}
| Foundry agent | Version | Tool connection → APIM route | Notes |
|---|---|---|---|
| `imh-uc-apim-umi-agent` (C) | **v6** | `uc-fn-via-apim-umi` (APIM key) → `/uc/mcp` | Step 6. Allow-list `imh_demo__clinical__get_patients`; no approval prompt |
| `imh-uc-limited-agent` (H) | **v3** | `uc-limited-via-apim-umi-iac` (APIM key) → `/uc-limited/mcp` | Step 7. Same allow-list; "leave `fac` out for all facilities" |

Joey's Foundry connections (`CMS-Data-Agent-Connection`, `aif-rjb-eu2`, `CRM-AgentSkill`, `FabricPowerBIMCP`): never touch.

## 6.2 Databricks: workspace `adb-rjb-wu3`, metastore `metastore_azure_westus3`
{widths: 1900 3160 4300}
| Object | Name | What it does |
|---|---|---|
| Catalog and schema | `imh_demo.clinical` | Holds the demo table and the two tool functions |
| Table | `patients` | 12 synthetic rows: SLC 4, OGDEN 3, PROVO 3, STGEORGE 2 |
| Row filter | `fac_filter` | `imh_phi_full` and `imh_analyst` see every facility; `imh_clinician_slc` sees SLC only |
| Column mask | `mask_name` | Real (synthetic) names for `imh_phi_full` and `imh_clinician_slc`; `REDACTED` for everyone else |
| Column mask | `mask_ssn` | Full value for `imh_phi_full`; `***-**-` plus the last 4 digits for everyone else |
| Table function | `get_patients(fac)` | MCP tool `imh_demo__clinical__get_patients`; leave `fac` out for all facilities |
| Table function | `get_patients_limited(fac, max_rows)` | Default 5 rows; Unity Catalog caps it at 10 whatever the agent asks |
| Group | `imh_phi_full` | jay: everything |
| Group | `imh_clinician_slc` | SLC only, names shown, SSN masked |
| Group | `imh_analyst` | All rows, names `REDACTED`, SSN masked. **APIM's identity is here** |
| Service principal | `umi-imh-uc-agent` | APIM's managed identity, added Oct 12 (images 8 and 9) |
| SQL warehouse | `adb-demo-wh` | Serverless; SQL editor, Genie and `ai_query` only. MCP calls don't use it |
| Serving endpoint | `imh-foundry-gpt41-via-apim` | External model → APIM `/aoai`; AI Gateway usage tracking, 60 calls a minute |
| Secret scope | `imh-apim` | Holds the APIM key for the serving endpoint; the setup script put it there from memory, never on disk |
| Genie One + Microsoft 365 | Connector signed in as jay, Oct 13 | Priority 2 backup (step 12) |

## 6.3 Oct 14 cleanup (Foundry only)
- Deleted agents A, B, G and K and their 3 OAuth tools (per-user Genie and UC paths, Genie through APIM, Genie One). Snapshot first: `JAY DEMO v2\evidence\foundry-agents-before-cleanup.json`.
- Fixed two agent behaviours seen in testing (sending `fac:""`, which returns 0 rows, and picking the wrong function): new versions C v6 and H v2 with a tool allow-list and the instruction to leave `fac` out for all facilities. H v3 (about 3:40 PM) is the same as v2 but references its connection by name, so the Foundry UI shows the tool.
- Databricks objects and APIM untouched. Items named `hls-*` belong to another demo and were left alone.
- Re-verified C, H, D, I and J live on Oct 14, 2:05–2:45 PM ET (section 7.1).

@img 07-foundry-agents-before-cleanup.png | Image 7. Foundry agents before the Oct 14 cleanup

## 6.4 Databricks identity setup (Oct 12)
@img 08-databricks-umi-added-to-workspace.png | Image 8. APIM's managed identity `umi-imh-uc-agent` added to the workspace as a service principal
@img 09-databricks-umi-added-to-imh_analyst.png | Image 9. The same identity added to group `imh_analyst`

## 6.5 Not ours: leave alone
- Two "HLS imaging" APIs in APIM (`/hls-genie`, `/hls-uc`) that point at another workspace.
- Container Apps jobs `job-hls-genie-mcp-demo` and `job-hls-uc-mcp-demo` in `rg-ai` (created Oct 13).
- Joey's Foundry connections listed in 6.1.

## 6.6 After Oct 15
- Remove the Databricks app connections left from the per-user segments: `foundry-genie-imh-uc` and `foundry-agent-genie-one-mcp-imh`.
- Rotate the APIM subscription keys and the BrakeKat sign-in that was shared by text.
- Move the plaintext credentials in `JAY DEMO v2\resources\` into a vault and delete them from the file.
- Run `terraform validate` on `infra\uc-agent-gateway\`.
