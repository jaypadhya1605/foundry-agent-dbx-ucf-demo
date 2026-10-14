# IMH onsite demo: Foundry agents ↔ Databricks Unity Catalog

**Onsite:** Thursday 2026-10-15, Intermountain Health (Mark Nielsen + IMH platform, cyber, DB admin).
**Owner:** Jay Padhya (Microsoft SE, HLS). **Data SE:** Joey Brakefield. **Architect:** Chris Tava.
**Background:** [IMH-thread-and-control-plane-context.md](./IMH-thread-and-control-plane-context.md)
**Evidence:** [evidence/brakekat-uc-proof/README.md](./evidence/brakekat-uc-proof/README.md), [evidence/proof-status.json](./evidence/proof-status.json)

---

## 1. The one-line answer for Mark

An Azure agent can query Databricks **through Unity Catalog, with UC as the only governance
layer**, using the pattern **Azure Agent → APIM → MCP Server → UC Function → Databricks Tables**.
This does **not** require External Data Access, because the function runs **inside** Databricks.
It does require an authorized identity, UC grants on the function and data, and a network path.
Fabric UC mirroring is a different path that **does** require External Data Access (and adds a
Fabric-side access layer), so it stays out of scope unless IMH signs off.

---

## 2. What the demo contains

All demo work runs in the **BrakeKat** tenant (Joey's) with **synthetic data only**.

### Environment

| Component | Value |
|---|---|
| Entra tenant | BrakeKat Studios (users: `jay@`, `clinician-slc@`, `analyst@brakekat.com`) |
| Foundry | `aif-wu3` (westus3, rg `rg-ai`) → project `proj-imh-uc-demo` |
| Databricks | workspace `adb-rjb-wu3` (`adb-2813105879250022.2.azuredatabricks.net`), metastore `metastore_azure_westus3` |
| Data | `imh_demo.clinical.patients` — 12 synthetic rows (patient_id, name, dob, ssn, facility, diagnosis) |
| UC groups | `imh_phi_full` (jay), `imh_clinician_slc`, `imh_analyst` |
| UC policies | Row filter `fac_filter` (phi_full sees all; clinician sees SLC), masks `mask_ssn`, `mask_name` |
| Compute | Serverless SQL warehouse `adb-demo-wh` (Genie); serverless compute (UC function MCP) |
| OAuth app | Databricks custom app `foundry-genie-imh-uc`, scopes `all-apis offline_access`; one redirect URL per Foundry connection |

### Demo segments

| # | Segment | Path | Status |
|---|---|---|---|
| A | **Genie through MCP, per-user** | Foundry agent `imh-uc-genie-agent-from-foundry` → Genie MCP (`/api/2.0/mcp/genie/<space>`) → UC → table | ✅ Passed (3 users) |
| B | **UC function through MCP, per-user** | Foundry agent `imh-uc-fnct-1-agent` → tool `uc-fn-imh-mcp-v3` (`/api/2.0/mcp/functions/imh_demo/clinical/get_patients`) → `get_patients(fac)` → table | ✅ Passed (3 users, 2026-10-12) |
| C | **APIM in the path, agent identity (UMI)** | Foundry agent → APIM BasicV2 (`authentication-managed-identity` with UMI `umi-imh-uc-agent`) → UC functions MCP → table. UMI = Databricks service principal in `imh_analyst`. IaC: `infra/uc-agent-gateway/` (Bicep + Terraform + Databricks Terraform; first deploy was `infra/brakekat-apim-umi.bicep`) | ✅ APIM→UC passed via script 2026-10-12 (4 SLC rows, REDACTED, masked). ✅ Foundry agent `imh-uc-apim-umi-agent` (tool `uc-fn-via-apim-umi`, key auth) passed 2026-10-12: same 4 rows, no Databricks sign-in, approval prompt shown in v3 and turned off in v5 |
| D | **Audit trail** | Same call seen in APIM `ApiManagementGatewayLogs` + Foundry trace + Databricks Query History (real user) | ✅ 2026-10-12. Databricks: Query History shows 3 `get_patients(fac => "SLC")` calls (4:41 script, 4:54 and 4:55 Foundry) as User `umi-imh-uc-agent`, Source Spark Connect API, serverless. APIM: `ApiManagementGatewayLogs` in `law-imh-uc-66zpmtcbvhe7w` shows the same calls (UTC 20:41/20:53/20:54/20:55) with ApimSubscriptionId `foundry-imh-uc-agent`, a CorrelationId on each call, and BackendUrl = Databricks MCP functions. Normal codes: POST 200 (initialize/tools/list/tools/call), POST 202 (MCP notification), GET 405 (client probes for a stream; Databricks declines it, harmless). Foundry trace: optional |
| E | **External Data Access not required** | BrakeKat metastore `metastore_azure_westus3` had EDA **Enabled**. Toggled **off** (Catalog → ⚙ → Metastore → Details) on 2026-10-12 ~8:17 PM, reran the agents, then restored | ✅ APIM/UMI agent returned the same 4 SLC rows (REDACTED, masked) with EDA **Disabled**. Per-user agent: rerun optional. EDA restored to Enabled for Joey |
| F | **Private network path** (Proof A, separate fdpo build) | Foundry → private APIM → ACA MCP → Databricks warehouse | ✅ Passed (`SELECT 1`), **no UC metastore** |
| G | **Genie through APIM (agent identity)** | Foundry agent `imh-genie-apim-umi-agent` → APIM `/genie/mcp` (key) → UMI → Genie space | ✅ 2026-10-13: "patients per facility" → SLC 4, OGDEN 3, PROVO 3, STGEORGE 2 + the SQL Genie wrote |
| H | **Gateway guardrails: row/size cap + rate limit + quota** | Foundry agent `imh-uc-limited-agent` / script → APIM `/uc-limited/mcp`: >5 rows or >20 KB blocked (MCP tool error + `x-imh-gateway-block`), 3 tool calls/min, 200/day | ✅ 2026-10-13: SLC = 4 rows; all facilities blocked "row-limit 12>5"; calls 4-5 in a minute → 429; agent told the user to narrow to one facility |
| I | **Custom runtime with Entra token, no key** (AKS stand-in) | Container Apps job `job-imh-uc-agent` (UMI `umi-imh-uc-runtime`) → APIM `/uc-entra/mcp` (`validate-azure-ad-token`, client allow-list) → UMI → UC | ✅ 2026-10-13: job got 4 SLC rows (masked); Jay's own token → 401. Interim audience = ARM (no app registration possible as guest) |
| J | **Databricks → APIM → Foundry model** | APIM `/aoai` (key in `api-key`, `llm-token-limit`, UMI → `aif-wu3` gpt-4.1); Databricks external-model endpoint `imh-foundry-gpt41-via-apim` + AI Gateway | ✅ APIM side 2026-10-13 ("gateway ok", token header). ⏳ Databricks endpoint: Jay runs `infra/uc-agent-gateway/databricks/Setup-DatabricksSide.ps1` |

### Expected results (segments A and B)

| User | UC group | Rows | Name | SSN |
|---|---|---|---|---|
| jay | `imh_phi_full` | all (12; SLC = 4) | full | full |
| clinician-slc | `imh_clinician_slc` | SLC only (4) | full | `***-**-1001` |
| analyst | `imh_analyst` | all permitted rows | `REDACTED` | `***-**-1001` |

Databricks **Query History** shows each call under the named end user, not a service principal.
Genie calls show source *Patient Clinical Records* on `adb-demo-wh`; UC function calls show
source *Spark Connect API* on serverless compute.

### Proposed day plan (Jay lands ~10:15, in room ~11:00)

| Time | Block | Lead |
|---|---|---|
| 8:30–9:15 | Intros, alignment; approved cloud infra review | Mark, Bryan, Yun, Chris G. |
| 9:15–10:00 | Scope, target resources, success criteria | Mark, Bryan |
| 10:00–11:00 | Databricks-side options: sharing paths, EDA vs. no-EDA, Fabric mirroring trade-offs | Joey |
| 11:00–11:15 | Buffer + Jay catch-up (Joey summarizes scope decisions) | Jay, Joey |
| **11:15–12:00** | **Live demo (25 min) + Q&A (20 min)** | Jay |
| 12:00–1:00 | Lunch (Jay sits with Bryan's team on their APIM/AKS setup) | — |
| 1:00–1:30 | Reconnect, status | Mark, Bryan |
| 1:30–3:00 | Hands-on in IMH tenant: register UMI as Databricks SP, UC grants, APIM → UC function MCP | All |
| 3:00–3:30 | Foundry observability + end-to-end (traces, evals, APIM logs, Query History); Fabric capabilities | Jay, Joey |
| 3:30–4:00 | Tasks, owners, follow-up demo for Brian, Andy, Shawn | Mark, Bryan |

Demo (25 min): per-user Genie, 3 users (7) → UC function, 3 users (5) → APIM + UMI agent identity (6)
→ audit: Query History + APIM logs, EDA off (4) → limitations (3).
Backup: recorded video + screenshots with Joey in case of flight delay.

### Run of show (afternoon breakout, ~30 min)

1. Architecture slide: IMH control plane (APIM + AKS + UMI + Agents 365) with the Databricks hop added; two identity modes.
2. Segment A as jay → clinician → analyst (same question, different answers).
3. Segment B: the same proof through a governed UC function (bounded tool, not free-form SQL).
4. Segment C/D: APIM policy hit (429), APIM log, Query History with real user.
5. Segment E: EDA Disabled screenshot.
6. Limitations (section 4) and next steps for IMH's own tenant.

---

## 3. Questions to ask IMH (Mark Nielsen and team)

### Identity

1. Should the agent act **as the end user** (OAuth passthrough — per-user UC rules, what we demo)
   or **as itself** (UMI / Entra Agent ID mapped to a Databricks service principal)? For PHI,
   which does cyber require?
2. Are the control-plane UMIs registered in **Agents 365 / Entra Agent ID**? Should the kill
   switch also cut Databricks access (disable the identity → no new tokens)?
3. Are Databricks and the agents in the **same Entra tenant**? (Required for clean SSO passthrough.)

### Network and platform

4. Is APIM **internal / VNet-injected**? Can it reach the Databricks workspace front-end over
   **Private Link**? Any IP access lists on the workspace?
5. Is **serverless compute** allowed in the workspace? (The UC-function MCP runs on serverless.)
6. Can IMH enable the **Managed MCP Servers** preview, or is there a policy against previews?
7. Do agents run on **AKS, ACA, or Foundry**? Are Foundry-hosted agents in scope at all?

### Ownership and operations

8. Who owns the **agent-tools schema** and its functions? Deployed via **DABs / CI**?
9. Who is in the room Thursday with **Databricks account admin** (OAuth app registration),
   **APIM owner**, and **Foundry project owner** rights?
10. What audit sink is required: Log Analytics, **Sentinel**, Databricks `system.access.audit`?
11. Which **non-PHI or synthetic table** can we use live on Thursday?
12. What does **"done"** look like Thursday afternoon: a working tool call in IMH's tenant, or a
    design sign-off?

### Confirm, don't ask

- External Data Access **stays off**.
- Fabric UC mirroring is a **separate path**, not part of Thursday. Alternatives (Joey): Fabric
  native sharing, Delta Sharing / OpenSharing, Clean Rooms, file sharing.
- Agenda: morning = cross-team strategy; afternoon = (a) Databricks tools → MSFT agents,
  (b) MSFT tools → Databricks agents.

---

## 4. Limitations of this demo (say these up front)

### Environment

- **Not IMH's tenant.** Runs in BrakeKat with synthetic data. IMH would run Foundry, APIM and
  Databricks in its own tenant with real SSO.
- **Public endpoints.** The Genie / UC-function MCP path over a **fully private** network is
  unproven. Proof A proved a private path but without a UC metastore. A Foundry project with its
  own private network hits the same MCP DNS/egress issue seen with APIM.
- **Small synthetic dataset** (12 rows, 4 facilities). No performance or scale claims.

### Identity

- **User passthrough only.** The **UMI / agent-identity** mode that IMH's control plane uses
  (AKS + UMI) is **not shown** yet. In that mode UC enforces the service principal's rights, not
  the end user's.
- **Agents 365 kill switch** is a talk track, not demoed.
- **OAuth consent binds whichever Databricks identity completes the popup.** With shared browser
  cookies, a Foundry user can end up holding someone else's Databricks token (we hit this; Query
  History caught it). Mitigation: same-tenant SSO, Conditional Access, audit Query History.
- Consent is stored **per user, per connection, per project**. Refresh tokens expire; re-consent
  before the demo.
- First consent shows a cosmetic **"Authentication failed / Code not found"** popup; "Sign in
  successful" in chat is what counts.

### Product / preview

- **Managed MCP Servers** is a Databricks **preview**. The legacy `/api/2.0/mcp/...` endpoints
  bypass Unity Gateway tracing.
- **Foundry AI Gateway for MCP** is **preview**, applies only to **newly created** tools, and
  not to managed OAuth.
- **Foundry OAuth tools can't be edited.** Any change (secret, URL) = delete + recreate, which
  issues a **new redirect URL** that must be added to the Databricks app.
- OAuth app uses **`all-apis`** scope (broad). Production should narrow scopes.
- New Foundry agents **auto-add Web search**; remove it.

### Behavior

- **Genie generates SQL** — answers can vary run to run. The UC function is the bounded,
  deterministic alternative.
- The LLM can mangle masked values in markdown (`***` → bold); agent instructions wrap values in
  backticks.
- UC-function calls run on **serverless compute** (cost and policy implications).

### Not covered (gaps vs. IMH asks)

| IMH ask | Gap |
|---|---|
| AKS/ACA agents with UMI → UC | ✅ Segment I (Container Apps job; AKS provider not registered in BrakeKat). Same client runs on AKS with `--auth workload` |
| MSFT tools → Databricks agents | ✅ Graph: Genie One chat + `system.ai.microsoft_365` wrote an Outlook draft from UC data (Oct 13, `evidence/brakekat-uc-proof/README.md`). Work IQ needs billing; Copilot Studio → Databricks is talk track only |
| Fabric UC mirroring | Out of scope (needs EDA, IMH declined) |
| Infrastructure as code | ✅ Bicep deployed + tested in BrakeKat. ⚠️ Terraform (Azure, reads shared policy XML) + Databricks Terraform written, `terraform validate` not yet run — see `infra/uc-agent-gateway/README.md` "Validation done" |
| Entra app registration for the gateway | Interim ARM audience + client allow-list in BrakeKat; IMH registers `api://imh-uc-gateway` |
| Private networking | Not rebuilt in BrakeKat (Segment F covers it without UC) |

### Security housekeeping

- Client secrets live only in Foundry connections. Rotate all demo secrets after 10/15 (they were
  shared in a document and chat).

---

## 5. Pre-demo checklist (Oct 14 dry run)

- [x] Segment B retest as clinician and analyst (Chrome / Firefox)
- [ ] Segment C: AI Gateway + governed tool + rate-limit + diagnostics
- [ ] Segment J: run `infra/uc-agent-gateway/databricks/Setup-DatabricksSide.ps1` as jay@brakekat.com (creates `get_patients_limited` + `imh-foundry-gpt41-via-apim`, tests `ai_query`)
- [ ] Segments G–I: rerun once (`foundry/create_agents.py --ask-only`, `az containerapp job start -n job-imh-uc-agent -g rg-ai`)
- [ ] Segment D: three-way evidence for one call
- [ ] Segment E: EDA Disabled screenshot
- [ ] One browser per user (never share cookies): **Edge = jay**, **Chrome Incognito = analyst**,
      **Firefox Private = clinician**. Don't sign in to the browser itself; sign in on the website.
      Agent deep link (forces BrakeKat tenant):
      `https://ai.azure.com/nextgen/r/m77hkNxhTFirRxJ1ywQBjw,rg-ai,,aif-wu3,proj-imh-uc-demo/build/agents/imh-uc-fnct-1-agent/build?tid=8d038e6a-9b7d-4cb8-bbcf-e84dff156478`
- [ ] Re-consent all three users; pre-warm `adb-demo-wh`
- [ ] Fallback screenshots for every segment
- [ ] Architecture slide with both identity modes
- [ ] Text Joey a summary of changes in his tenant
