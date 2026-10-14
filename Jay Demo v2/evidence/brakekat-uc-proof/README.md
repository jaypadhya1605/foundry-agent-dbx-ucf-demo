# Proof B: per-user Unity Catalog through Foundry + Genie MCP (BrakeKat tenant)

**Status:** PASSED, 2026-10-12 00:10 ET.
**Scope:** separate demo tenant (BrakeKat Studios, Joey Brakefield), **public**
endpoints, **synthetic** data. Not IMH, and not the private fdpo build (Proof A).

## What it proves

One Foundry agent, one Genie connection, one question
(`List all patients with patient_id, name, ssn and facility.`). Each person
signs in as themselves through OAuth identity passthrough, and Unity Catalog
enforces that person's own row filter and column masks. Databricks Query
History attributes each query to the named end user, not a service principal.

| User | UC group | Rows | Name | SSN | Query History |
|---|---|---|---|---|---|
| jay@brakekat.com | `imh_phi_full` | 12 | full | full | 23:28 ET |
| clinician-slc@brakekat.com | `imh_clinician_slc` | 4 (SLC) | full | `***-**-1001` | 23:39 ET |
| analyst@brakekat.com | `imh_analyst` | 12 | `REDACTED` | `***-**-1001` | 00:02 ET |

## Components

- **Foundry:** `aif-wu3` (westus3) → project `proj-imh-uc-demo` → agent
  `imh-uc-genie-agent-from-foundry` v4 (gpt-4.1, Genie tool only).
- **Connection:** `genie-imh-uc`, OAuth identity passthrough, custom Databricks
  OAuth app `foundry-genie-imh-uc` (scopes `all-apis offline_access`).
  The secret lives only in the Foundry connection.
- **Databricks:** workspace `adb-rjb-wu3` (2813105879250022), metastore
  `metastore_azure_westus3`, Genie space *Patient Clinical Records*
  (`01f1c5e2508a1326a03ad64e4d7fb1b5`), serverless warehouse `adb-demo-wh`.
- **Data/policies:** `imh_demo.clinical.patients` (12 synthetic rows), row
  filter `fac_filter`, masks `mask_ssn` and `mask_name`.
- **Azure RBAC (project scope):** jay = Foundry User + Contributor; test users =
  Foundry User (+ Reader on the account so the portal lists the project).

## Screenshots to save here

| File | Shows |
|---|---|
| `01-jay-phi-full.png` | Agent answer as jay: 12 rows, full values |
| `02-clinician-slc.png` | Agent answer as clinician: 4 SLC rows, masked SSN |
| `03-analyst.png` | Agent answer as analyst: 12 rows, REDACTED, masked SSN |
| `04-query-history-three-users.png` | Query History, same SELECT, three named users |
| `05-agent-v4-tools.png` | Agent v4: Genie tool only, instructions |
| `06-genie-one-facilities.png` | Genie One chat as jay: patients per facility + SQL |
| `07-outlook-draft-from-genie-one.png` | Outlook Drafts: "Patients per Facility Summary" written by Genie One |
| `08-k-jay.png` | Segment K as jay: 12 rows, full values (agent v6) |
| `09-k-clinician.png` | Segment K as clinician: 4 SLC rows, masked SSN |
| `10-k-analyst.png` | Segment K as analyst: 12 rows, REDACTED, masked SSN |
| `11-k-query-history.png` | Query History: the three Segment K queries, three named users |
| `12-k-ai-gateway-usage.png` | `system.ai_gateway.usage`: Genie One MCP calls by `requester` |

## Segment B: UC function through MCP (2026-10-12)

Agent `imh-uc-fnct-1-agent` v11 (gpt-4.1) → custom MCP tool `uc-fn-imh-mcp-v3`
(`/api/2.0/mcp/functions/imh_demo/clinical/get_patients`, OAuth identity
passthrough, same Databricks OAuth app) → `get_patients(fac)` → table.
Prompt: `Show me patients at SLC.` → tool call `imh_demo__clinical__get_patients({"fac":"SLC"})`.

| User | Browser | Rows | Name | SSN |
|---|---|---|---|---|
| jay | Edge | 4 (SLC) | full | full |
| analyst | Chrome Incognito | 4 (SLC) | `REDACTED` | masked (last 4) |
| clinician-slc | Firefox Private | 4 (SLC) | full | masked (last 4) |

UC row filter and masks apply through the function for the invoking user.
Calls run on serverless compute (Query History source "Spark Connect API").

**Lesson:** a first analyst attempt returned jay's data because a shared
InPrivate session completed the Databricks consent as jay. Query History
showed every call as jay, so this was token binding, not a UC bypass. Fix:
delete/recreate the Foundry tool (OAuth tools can't be edited), one browser
per user.

## Segments C, G, H, I and /aoai: APIM gateway + runtime (2026-10-12/13)

Deployed with `infra/uc-agent-gateway/azure/bicep`. Databricks sees the APIM managed identity
`umi-imh-uc-agent` (service principal in `imh_analyst`), not the end user.

| Segment | Path | Result |
|---|---|---|
| C | `/uc/mcp` (key) | 4 SLC rows, REDACTED, masked SSN; agent `imh-uc-apim-umi-agent` |
| G | `/genie/mcp` (key) | agent `imh-genie-apim-umi-agent`: per-facility counts + SQL |
| H | `/uc-limited/mcp` (key) | SLC 4 rows; all facilities blocked (`x-imh-gateway-block: row-limit 12>5`); 4th call/min = 429; agent `imh-uc-limited-agent` asks to narrow |
| I | `/uc-entra/mcp` (Entra token, no key) | Container Apps job `job-imh-uc-agent` (UMI `umi-imh-uc-runtime`): 4 SLC rows, 200. Jay's az cli token: 401 |
| J (APIM side) | `/aoai` | 200 "gateway ok" via managed identity to Foundry gpt-4.1 |
| J (Databricks side) | endpoint `imh-foundry-gpt41-via-apim` → `/aoai` | 2026-10-13, `Setup-DatabricksSide.ps1` as jay@brakekat.com: `get_patients_limited` returned 5 rows by default and 10 when 50 were asked for (not all 12). Secret `imh-apim/aoai-key` holds the APIM key, not the Foundry key. Endpoint READY with AI Gateway usage tracking and 60 calls/min. REST call returned "databricks to foundry via apim ok"; SQL `ai_query` answered |

Not executed: `terraform validate`.
Caveats: Container Apps stands in for AKS; interim Entra audience is ARM + client allow-list; public network.
The Databricks side uses the serving endpoint's AI Gateway (now labeled legacy); the newer Unity Gateway equivalent is a
model provider service in Unity Catalog. Log of the run: `%TEMP%\imh-setup-databricks-side.log` on Jay's laptop.

## IMH priority 2: Genie One chat → Microsoft 365 (2026-10-13)

Databricks' own agent (Genie One chat, `/one/chat`) as jay@brakekat.com (`imh_phi_full`), using two Unity Gateway
MCPs: `system.ai.genie_one_mcp` (UC data) and `system.ai.microsoft_365` (Microsoft Graph through Databricks' managed
OAuth app). Jay signed in from **+** → Microsoft 365 and left *Consent on behalf of your organization* unticked
(consent for himself only). No app registration, no code.

| Test | Result |
|---|---|
| "How many patients per facility?" | 12: SLC 4, PROVO 3, OGDEN 3, STGEORGE 2 (SQL on `imh_demo.clinical.patients`) |
| Read: "list my 3 most recent emails" | Nothing returned: the mailbox is new and empty (not a permission error) |
| Write: draft the summary to clinician-slc | Outlook Drafts, 11:52 AM: "Patients per Facility Summary", facility table, "Total: 12 patients across 4 facilities". Not sent (the connector drafts only) |

Outlook flags `clinician-slc@brakekat.com` as not valid because that user has no mailbox; don't send the draft.
Each user needs a Microsoft 365 seat with a mailbox and signs in for themselves. At IMH the Microsoft 365 admin
approves Databricks' Microsoft 365 app and its `.All` scopes, and compliance clears PHI moving between Microsoft 365
and Databricks in both directions. Not on Yun's diagram (it draws only ⑤ for Databricks → Microsoft).

## Segment K: Genie One MCP through Unity Gateway, per user (2026-10-14)

IMH priority 1 on Databricks' GA endpoint (Yun ④, Genie box). Agent `foundry-agent-2-genie-one-imh` (gpt-4.1) → custom
MCP tool `Fndry-tool-genie-ai-gateway` (OAuth identity passthrough, Databricks app connection
`foundry-agent-genie-one-mcp-imh`, scope `ai-gateway`) →
`https://adb-2813105879250022.2.azuredatabricks.net/ai-gateway/mcp-services/system.ai.genie_one_mcp` → Genie One → UC.
Unlike segments A and B, the call passes Unity Gateway, so it needs `EXECUTE` on the MCP (all account users inherit it
from `system.ai`) and is logged in `system.ai_gateway.usage`.

| User | Browser | Agent | Rows | Name | SSN | Time |
|---|---|---|---|---|---|---|
| jay | Edge | v6 | 12 (4 facilities) | full | full | 1:13 PM ET, ~68 s |
| clinician-slc | Firefox Private | v6 | expect 4 (SLC) | expect full | expect masked | pending |
| analyst | Chrome Incognito | v6 | expect 12 | expect `REDACTED` | expect masked | pending |

The v4 try (12:33 PM) signed in fine, but Genie One rejected the call: gpt-4.1 sent an empty `conversation_id`
(`must be alphanumeric … got ''`). v6 instructions: leave it out on a new question, poll until `completed`, fetch the
rows with `genie_get_query_result`, wrap values in backticks.

## Option 2 only: cleanup, agent fix and re-verification (2026-10-14, ~2:00–2:15 PM ET)

The onsite now shows Option 2 only (UC functions + MCP + APIM). Snapshot of every agent before deletion:
`JAY DEMO v2/evidence/foundry-agents-before-cleanup.json`. Databricks: nothing deleted.

| Change | Detail |
|---|---|
| Deleted Foundry agents | `foundry-agent-2-genie-one-imh` (K), `imh-genie-apim-umi-agent` (G), `imh-uc-fnct-1-agent` (B), `imh-uc-genie-agent-from-foundry` (A) |
| Deleted Foundry OAuth tools | `genie-imh-uc`, `uc-fn-imh-mcp-v3`, `Fndry-tool-genie-ai-gateway` |
| Kept | Agents `imh-uc-apim-umi-agent` (C) and `imh-uc-limited-agent` (H); key connections `uc-fn-via-apim-umi`, `uc-fn-via-apim-umi-iac`, `genie-via-apim-umi-iac`, `uc-limited-via-apim-umi-iac` |
| Bug found | H v1, asked for all facilities, called `get_patients_limited` with `fac: ""`: 0 rows, so the APIM cap never fired |
| Fix | C v6 and H v2: MCP tool allow-list `imh_demo__clinical__get_patients` only, and "leave `fac` out (never an empty string) for all facilities". Same change in `infra/uc-agent-gateway/foundry/create_agents.py` (`--allowed-tools`) |

| Re-test | Result |
|---|---|
| `/uc/mcp` script, `tools/list` | `get_patients`, `get_patients_limited` only (scalar mask/filter functions aren't tools) |
| `/uc/mcp` script, SLC | 4 rows, REDACTED, `***-**-1001..1004`; ~22 s cold |
| `/uc-entra/mcp` with Jay's az cli token | 401 "A valid Entra token for the UC agent gateway is required." |
| C v6 "patients at SLC" / "all patients" | `get_patients {"fac":"SLC"}` 4 rows (~7 s) / `get_patients {}` 12 rows, all masked |
| H v2 "all patients across every facility" | Blocked: "the result has 12 rows (limit 5)…". The REST API surfaces it as HTTP 400 `tool_user_error`; the portal shows it as a tool error or the agent rewords it. Then "SLC" → 4 rows |
| I (job execution `job-imh-uc-agent-597gxc7`) | Succeeded in 39 s: `/uc-entra/mcp`, `auth=mi`, HTTP 200, 4 SLC rows masked |
| J (SQL statement API on `adb-demo-wh`) | `ai_query('imh-foundry-gpt41-via-apim', …)` answered; `get_patients_limited(NULL, 50)` → 10 rows; caller `jay@brakekat.com` |
| D | Query History: ``get_patients(fac => "SLC")``, Spark Connect, serverless compute, user `umi-imh-uc-agent`. APIM logs: blocked calls still show 200 (the policy returns an MCP error inside a 200) |

## Caveats (say these up front)

- Cross-tenant from Microsoft's side: Foundry passthrough requires the user to
  be in the Foundry project's Entra tenant, so both Foundry and Databricks sit
  in BrakeKat here. IMH would run both in its own tenant (true single-tenant SSO).
- Public network. Genie MCP over a fully private path is still unproven and is a
  joint test for the onsite breakout.
- First consent per user shows an "Authentication failed / Code not found"
  popup even though sign-in succeeds; close it (preview UI quirk).
- The Databricks consent screen says "Created by jay@brakekat.com"; that is the
  OAuth app's publisher label, not the signed-in user.
