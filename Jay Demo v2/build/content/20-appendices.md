# Appendix A. IDs and URLs {#appa}

{widths: 2800 6560}
| Item | Value |
|---|---|
| Tenant (BrakeKat) | `8d038e6a-9b7d-4cb8-bbcf-e84dff156478` |
| Subscription | Azure-brakekat, `9bbee190-dc61-4c58-ab47-1275cb04018f` |
| Resource group | `rg-ai` (West US 3) |
| APIM gateway | `https://apim-imh-uc-66zpmtcbvhe7w.azure-api.net`<br>MCP: `/uc/mcp`, `/uc-limited/mcp`, `/uc-entra/mcp`. Model: `/aoai` |
| APIM identity → Databricks | `umi-imh-uc-agent`, client ID `e983157d-68fc-430a-9ee8-cdf1efe4b68e` |
| Runtime identity | `umi-imh-uc-runtime`; the only app allowed on `/uc-entra` is `dbd7f6a1-92a8-470b-a7bd-7bf2f947b6a7` |
| Databricks token audience | `2ff814a6-3304-4ab8-85cb-cd0e6f879c1d` (the Azure Databricks application) |
| Log Analytics | `law-imh-uc-66zpmtcbvhe7w`, workspace ID `abf8c64e-99ad-4faf-b61b-fac726ddee36` |
| Databricks workspace | `adb-rjb-wu3`: `https://adb-2813105879250022.2.azuredatabricks.net` |
| Databricks MCP backend | `https://adb-2813105879250022.2.azuredatabricks.net/api/2.0/mcp/functions/imh_demo/clinical` |
| Table page | `https://adb-2813105879250022.2.azuredatabricks.net/explore/data/imh_demo/clinical/patients?o=2813105879250022` |
| Query History | `https://adb-2813105879250022.2.azuredatabricks.net/sql/history?o=2813105879250022&preset=d_last_hour` |
| SQL warehouse | `adb-demo-wh` (`040e0ffa3b290340`) |
| Serving endpoint | `imh-foundry-gpt41-via-apim` → APIM `/aoai`; key in secret scope `imh-apim` |
| Databricks account console | `https://accounts.azuredatabricks.net` (account `082cbe91-b8ca-4ac2-bae1-28b83b85267e`) |
| Genie space (not shown) | `01f1c5e2508a1326a03ad64e4d7fb1b5` |
| Foundry agent C | `https://ai.azure.com/nextgen/r/m77hkNxhTFirRxJ1ywQBjw,rg-ai,,aif-wu3,proj-imh-uc-demo/build/agents/imh-uc-apim-umi-agent/build?tid=8d038e6a-9b7d-4cb8-bbcf-e84dff156478` |
| Foundry agent H | The same link with `imh-uc-limited-agent` |
| IMH sandbox | `https://adb-7405605832508369.9.azuredatabricks.net` |
| MSX | Opportunity 7-3HFNQXLBBY, "FY27 · Intermountain · AI Agent Landing Zone". After the onsite, and only with Jay's OK, log the activity on the **milestone**, never on the opportunity |

# Appendix B. Unity Catalog objects (SQL) {#appb}

The table, rules and tool functions as code: `infra\uc-agent-gateway\databricks\terraform\uc_objects.sql.tftpl`, shown with the demo names. Grants aren't in this file. The setup gives the three groups USE CATALOG, USE SCHEMA, SELECT and EXECUTE, plus Can use on `adb-demo-wh`. APIM's identity gets them through `imh_analyst`.

@sql

# Appendix C. APIM policies {#appc}

Rendered from `infra\uc-agent-gateway\azure\policy-*.xml` with the live values; comments removed.

> NOTE: No key or secret is stored in any policy. APIM signs in to Databricks and Foundry with its managed identity, and every route deletes the caller's key and token headers before forwarding.

## C.1 `/uc`: key + managed identity
@policy mcp-key

## C.2 `/uc-limited`: rate, quota, row and size cap
@policy mcp-limited

## C.3 `/uc-entra`: Entra token, no key
@policy mcp-entra

## C.4 `/aoai`: Databricks → Foundry model
@policy model

# Appendix D. Commands {#appd}

Run in PowerShell from the session folder. Read-only, except starting the job. Keys go only into `$env:` variables; never print them.

```powershell
$repo = "c:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session"
$client = "$repo\infra\uc-agent-gateway\clients\python_mcp_client.py"
$apim = "https://apim-imh-uc-66zpmtcbvhe7w.azure-api.net"
$subs = "https://management.azure.com/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/apim-imh-uc-66zpmtcbvhe7w/subscriptions"

# C path (/uc): warm-up + 4 SLC rows
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$subs/foundry-imh-uc-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
python $client --url "$apim/uc/mcp" --facility SLC

# H path (/uc-limited): all facilities -> blocked; --repeat 5 -> 429 on call 4
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$subs/imh-uc-limited-client/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
python $client --url "$apim/uc-limited/mcp" --args '{}'

# I path: Jay's own token -> 401 (expected)
python $client --url "$apim/uc-entra/mcp" --auth azcli --audience https://management.azure.com --list

# I job run (then read its logs ~2 min later)
az containerapp job start -n job-imh-uc-agent -g rg-ai
az monitor log-analytics query -w abf8c64e-99ad-4faf-b61b-fac726ddee36 --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(30m) | project TimeGenerated, Log_s | order by TimeGenerated asc"

# D: APIM logs, Databricks Query History
az monitor log-analytics query -w abf8c64e-99ad-4faf-b61b-fac726ddee36 --analytics-query "ApiManagementGatewayLogs | where TimeGenerated > ago(4h) | project TimeGenerated, ApiId, Method, ResponseCode, ApimSubscriptionId, CorrelationId | order by TimeGenerated desc"
databricks query-history list --max-results 10 -p brakekat -o json

Remove-Item Env:APIM_SUBSCRIPTION_KEY
```

The Databricks CLI profile `brakekat` signs in as `jay@brakekat.com`. `az` must be on subscription Azure-brakekat in the BrakeKat tenant.

**KQL for tab 8** (Log Analytics → Logs):
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(4h)
| project TimeGenerated, ApiId, Method, ResponseCode, ApimSubscriptionId, CorrelationId, BackendUrl
| order by TimeGenerated desc
```

**Rebuild this document** (close it in Word first; run from `$repo`):
```powershell
node "JAY DEMO v2\build\build-docx.mjs"
$env:PYTHONUTF8 = '1'
python "$env:USERPROFILE\.copilot\skills\docx\scripts\office\validate.py" "JAY DEMO v2\IMH-Option2-Dry-Run-and-Workflow.docx"
```
To change the text, edit `JAY DEMO v2\build\content\*.md`. Every PNG in `JAY DEMO v2\images\evidence\` is added to section 7.8.

# Appendix E. File index {#appe}

{widths: 4200 5160}
| File | Use |
|---|---|
| `JAY DEMO v2\dry-run-agent.md` | The dry-run playbook: a new chat reads it and coaches Jay step by step |
| `JAY DEMO v2\IMH-Option2-Dry-Run-and-Workflow.docx` | This document: flight reading and in-room fallback |
| `JAY DEMO v2\build\build-docx.mjs` | Builds this document |
| `JAY DEMO v2\build\content\*.md` | The text of this document, one file per section |
| `JAY DEMO v2\images\01`–`19` | Diagram, slide and proof screenshots (05 and 06 removed: IMH Teams content) |
| `JAY DEMO v2\images\evidence\` | Screenshots from the dry run |
| `JAY DEMO v2\dry-run-log.md` | Step log written during the dry run |
| `JAY DEMO v2\evidence\foundry-agents-before-cleanup.json` | Agent definitions before the Oct 14 cleanup |
| `Jay DEMO\claude-imh-dbx-foundry-demo.md` | Full demo record (segments A–K, questions for IMH) |
| `Jay DEMO\learn-tomorrow-must-should-build.md` | Yun mapping and learning route |
| `Jay DEMO\IMH-thread-and-control-plane-context.md` | People and the IMH thread |
| `Jay DEMO\evidence\brakekat-uc-proof\README.md` | Proof record, including the Oct 14 re-test |
| `infra\uc-agent-gateway\` | IaC, policies, smoke client, agent script |
| `JAY DEMO v2\resources\` | Older Oct 13 copies; not the source of truth. One file holds plaintext credentials: move them to a vault |
