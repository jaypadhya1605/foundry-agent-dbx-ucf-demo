# MUST + SHOULD build, mapped to Yun's diagram

Target: Yun's *Simplified Agent Network Path – Foundry ↔ APIM ↔ Databricks*. ①–⑥ are Yun's step numbers.
Everything below lives in BrakeKat `rg-ai` (West US 3), uses synthetic data, runs on public endpoints and is IaC in
[`infra/uc-agent-gateway/`](../infra/uc-agent-gateway/README.md).

- **"7 additions"** = the first IaC deploy: Genie API + its 3 operations + policy + key, plus Foundry connection
  `uc-fn-via-apim-umi-iac`.
- **MUST** = Genie through APIM (④ for Genie) + row/size cap (open item 2).
- **SHOULD** = Entra token + agent runtime (③, AKS box, open items 3–4) + Databricks → APIM → Foundry model (⑤, ⑥).

## 0. Scope check: IMH's two priorities

1. **Microsoft agents → Databricks tools.** Partly: Foundry agents only, on Databricks' legacy MCP endpoints. Genie
   One MCP is Active in BrakeKat but nothing calls it yet.
2. **Databricks agents ↔ Work IQ, Graph and other Microsoft MCP servers (both directions).** Graph part proven Oct 13:
   Genie One chat (Databricks' agent) queried UC as Jay and wrote an Outlook draft through `system.ai.microsoft_365`.
   Work IQ, Microsoft Learn MCP and the reverse direction aren't built. Yun's diagram only draws the model part (⑤);
   the reverse direction is ① (Teams / M365 Copilot / Copilot Studio).

| Priority | Path | Status |
|---|---|---|
| 1 | Foundry → Genie Agent MCP (Databricks' new name for a Genie space), per user (Proof B) and via APIM `/genie` | ✅ legacy endpoint |
| 1 | Foundry and the Container Apps runtime → UC functions MCP, per user and via APIM `/uc`, `/uc-limited`, `/uc-entra` | ✅ legacy endpoint |
| 1 | Genie One MCP `system.ai.genie_one_mcp` (GA, through Unity Gateway) | 🟡 listed and Active (Oct 13). Genie One chat as Jay ✅: 12 patients (SLC 4, PROVO 3, OGDEN 3, STGEORGE 2), SQL on `imh_demo.clinical.patients`. No Microsoft agent calls the MCP yet |
| 1 | Databricks SQL MCP, AI Search (formerly Vector Search) MCP | ❌ legacy *DBSQL MCP Server (Beta)* is listed but unused; `system.ai.dbsql` needs the account-level Unity Gateway beta, which is off |
| 1 | Copilot Studio / M365 Copilot → Databricks (Yun ①) | ❌ |
| 2 | Databricks → Foundry models through APIM `/aoai` (Yun ⑤) | 🟡 scripted, not run |
| 2 | Databricks → Microsoft Graph: built-in `system.ai.microsoft_365` (SharePoint, OneDrive, Outlook, Teams; per-user OAuth) | ✅ Oct 13, Genie One chat as Jay: **+** → Microsoft 365 → sign in (consent for self only; no app registration, no code), then it drafted an Outlook email to clinician-slc with the UC facility table (12 patients, 4 facilities). The read test returned nothing because the inbox is new and empty. Each user needs a Microsoft 365 seat with a mailbox (E5 here; BrakeKat has 2 free) |
| 2 | Databricks → Work IQ MCP, registered as an external MCP in Unity Gateway | ❌ no Microsoft 365 Copilot licenses in BrakeKat, so it needs pay-as-you-go Copilot Credits on an Azure subscription (Joey's cost) + one-time Global Admin setup |
| 2 | Databricks → Microsoft Learn MCP (public, no sign-in), registered as an external MCP | ❌ quickest proof |
| 2 | Reverse: Foundry agent with the Work IQ tool (preview) + Genie; Copilot Studio → Genie One MCP | ❌ |
| 2 | A Databricks agent to use these tools | ✅ Genie One chat (Databricks' own agent, nothing to build) used the Microsoft 365 tool on Oct 13. Supervisor Agent if we need a custom one (West US 3 supports it) |

**Databricks docs changed on Oct 7–8, 2026.** MCP now runs through **Unity Gateway** (BrakeKat menu: AI/ML → **AI Gateway**;
the page it opens is titled **Unity Gateway**; MCP URL `https://<workspace>/ai-gateway/mcp-services/<name>`), with Unity Catalog grants, policies and tracing per MCP. The Genie
Agent and UC functions endpoints under `/api/2.0/mcp/...` that everything here uses are now labelled *legacy*: still
supported for existing integrations, but they bypass Unity Gateway. The Genie One beta endpoint `/api/2.0/mcp/genie`
(no space ID) sunsets on Oct 31, 2026; nothing here uses it. Work IQ data can leave the Azure compliance boundary
(Foundry docs warning), so IMH has to clear it for PHI.

### What Unity Gateway → MCPs shows in BrakeKat (Oct 13)

| Row | What it is | Yun's box | Priority |
|---|---|---|---|
| `genie_one_mcp` (`system.ai`) | Genie One: answers across the workspace, first picking a matching Genie Agent | Databricks managed MCP: Genie (④) | 1, not used yet |
| `microsoft_365` (`system.ai`) | Databricks → Microsoft Graph (SharePoint, OneDrive, Outlook, Calendar, Teams); each user signs in | Not on Yun's diagram | 2 ✅ (Oct 13: Outlook draft from UC data) |
| *Patient Clinical Records* | Our Genie Agent `01f1c5e2…` on the legacy endpoint; Foundry Proof B and APIM `/genie` call it | ④ today | 1 ✅ |
| `imh_demo.clinical` (fx) | Our UC functions on the legacy endpoint; Foundry and APIM `/uc`, `/uc-limited`, `/uc-entra` call it | ④ today | 1 ✅ |
| *DBSQL MCP Server (Beta)*; atlassian, github, gmail, google_*, slack | Legacy SQL endpoint; other SaaS connectors | — | Not needed |

`system.ai` rows are Unity Catalog objects: callers need `EXECUTE` on the MCP, Unity Gateway records each call in
system tables, and MCP policies can block a call or its result (for example the built-in Sensitive Data Detection
policy on `class.us_ssn`; policies need the account-level Unity Gateway beta). Legacy rows skip Unity Gateway; the
table, function and warehouse permissions (our row filter and masks) still apply.

**Design point for ④:** Yun draws Unity AI Gateway only on the model path (⑤). As of last week Databricks also routes
MCP tools through it, so a ④ call to `system.ai.genie_one_mcp` passes two gateways: APIM (Microsoft side: Entra token,
rate limits, logs), then Unity Gateway (Databricks side: who may call which MCP, guardrails, tracing). Unity Catalog
still decides the rows. Our APIM APIs call the legacy rows, so Unity Gateway isn't in that path yet.

**Both priorities without code:** Priority 1 = Foundry agent → `genie_one_mcp`. Priority 2 = Genie One chat
(Databricks' agent) + `microsoft_365` (✅ Oct 13). Work IQ is the only piece that needs billing.

## 1. Yun's diagram → BrakeKat

| Yun | Box / step on Yun's diagram | What we built in BrakeKat | Status |
|---|---|---|---|
| ① | Caregivers in Teams / M365 Copilot, Copilot Studio agents (Entra sign-in) | Not built. Per-user Entra sign-in proven with Foundry agents instead (Proof B, direct to Databricks) | ❌ |
| ② | Cloudflare → App Gateway (WAF), public HTTPS | Not built (networking) | ❌ |
| | Agent Runtime – AKS | Container Apps job `job-imh-uc-agent` with its own managed identity `umi-imh-uc-runtime`, no secrets | 🟡 stand-in |
| | Foundry Agent Service (public DNS for tools) | 3 agents in `proj-imh-uc-demo` call APIM by its public name | ✅ |
| ③ | APIM validates the Entra token, applies policy, routes to the MCP tool | `/uc-entra`: token check + allowed-app list (runtime 200, Jay's token 401). `/uc`, `/genie`, `/uc-limited`: key + rate limits | ✅ interim audience |
| ④ | APIM → Databricks managed MCP / Genie / UC, OAuth M2M via Entra | APIM signs in as `umi-imh-uc-agent` (Entra token, no secret) = Databricks service principal in `imh_analyst` | ✅ identity, ❌ DMZ network |
| | Databricks managed MCP: Genie · UC functions · Vector Search | Genie Agent ✅ and UC functions ✅ (legacy endpoints); Genie One MCP ❌; AI Search (formerly Vector Search) ❌ | 🟡 |
| | Unity Catalog governs access | Row filter + name/SSN masks on `imh_demo.clinical.patients` decide the rows on every path | ✅ |
| ⑤ | Databricks Agents → Unity AI Gateway → APIM → Foundry models | APIM `/aoai` → gpt-4.1 ✅. Databricks endpoint with AI Gateway scripted, not run. No Databricks agent | 🟡 |
| ⑥ | AKS / APIM → Foundry model endpoints, private endpoint over VNet peering | APIM `/aoai` → Foundry over the public network. The runtime job doesn't call a model yet | 🟡 |
| | Entra ID: user sign-in, agent identities, M2M service principals | Users jay / clinician-slc / analyst, `umi-imh-uc-runtime`, `umi-imh-uc-agent` | ✅ |
| | West US 2 + East US 2 with VNet peering | Everything in West US 3, no peering | ❌ |

**Design point:** in Yun's ④ Databricks sees a service principal (M2M), not the caregiver. That is exactly the APIM
path here: UC applies the `imh_analyst` rules to everyone who comes through it. If IMH needs per-caregiver rows,
that's the per-user sign-in path from Proof B, which is not on Yun's diagram.

## 2. Yun's open items for Thursday

| Open item | Where we are |
|---|---|
| APIM ↔ Databricks serverless connectivity (DMZ) | Identity and protocol proven (④). Network not built. Review it per direction: APIM → Databricks = Private Link to the workspace; Databricks serverless → APIM (⑤) = serverless egress (NCC). |
| Result-size / row limits via APIM MCP | ✅ `/uc-limited`: more than 5 rows or 20 KB comes back as an MCP tool error; the 4th tool call in a minute gets a 429; 200 calls/day quota. |
| Confirm AKS as standard runtime | 🟡 The same client runs in the Container Apps job; on AKS only the sign-in changes (workload identity). |
| Foundry public DNS limitation → runtime on AKS | ✅ Both runtimes call the same governed APIM tool. Proof A (Jay's MCAPS build) had a private-network Foundry agent reach a private APIM (10.86.1.12); raise it with Yun (no UC in that test). |

## 3. BrakeKat sketch

```
Foundry agents ──key──┐
Container Apps job ───Entra token──┐
                      ▼            ▼
                 APIM apim-imh-uc-66zpmtcbvhe7w
   /uc  /genie  /uc-limited  /uc-entra            /aoai
     │     │        │            │                   │
     └─────┴── UMI umi-imh-uc-agent ──┘          UMI → Foundry gpt-4.1
                 │                                   ▲
         Databricks MCP, legacy URLs                 │
                 │                          Databricks external-model endpoint
          Unity Catalog (row filter, masks)  (AI Gateway; Jay runs setup)
```

## 4. Talk track (30 seconds each)

| Piece | Say this |
|---|---|
| ④ **Genie via APIM** (`/genie/mcp`) | "The same gateway that governs tool calls also fronts Genie. The agent asks in English, Genie writes the SQL, and UC decides the rows. APIM just signs in as the agent identity and logs it." |
| Open item 2: **Row/size cap** (`/uc-limited/mcp`) | "APIM can't see PHI rules, and it shouldn't. But it can stop a runaway agent: more than 5 rows or 20 KB comes back as a tool error, and more than 3 calls a minute gets a 429. UC still filters; APIM limits the blast radius." |
| ③ **Entra token, no key** (`/uc-entra/mcp`) | "Your AKS agents don't need a shared key. APIM validates their Entra token and only accepts listed client app IDs. My own token gets a 401 because I'm not on the list." |
| AKS box: **Agent runtime** (Container Apps job) | "This stands in for your AKS pod: a Python agent with its own managed identity, no secrets in the container. On AKS it's the same code with workload identity." |
| ⑤ ⑥ **Databricks → APIM → Foundry model** (`/aoai`) | "Model calls from Databricks go through the same APIM: token limits, logging and a managed identity to Foundry. Databricks AI Gateway adds usage tracking on its side." |

## 5. Learning route (Yun's order)

Azure portal in the BrakeKat directory; Databricks and Foundry as `jay@brakekat.com`.

1. **APIM box.** `rg-ai` → `apim-imh-uc-66zpmtcbvhe7w` → **APIs**. Five APIs: `/uc`, `/genie`, `/uc-limited`,
   `/uc-entra`, `/aoai`.
2. **③ Token check.** *IMH UC functions MCP - Entra token (no key)* → *All operations* → Inbound processing `</>`.
   Find `validate-azure-ad-token` (allowed app `dbd7f6a1…` = runtime identity), `rate-limit-by-key` (throttling),
   `rewrite-uri` (route to the UC functions MCP).
3. **④ OAuth M2M.** Same policy, last line: `authentication-managed-identity resource="2ff814a6-…"` (Azure
   Databricks' app ID). APIM gets an Entra token as `umi-imh-uc-agent`; no secret. Databricks → Settings → Identity
   and access → Groups → `imh_analyst` → Members: `umi-imh-uc-agent`.
4. **Unity Catalog box.** Catalog → `imh_demo` → `clinical` → `patients`: row filter `fac_filter`, masks on `ssn` and
   `name`. Query History → filter by the `umi-imh-uc-agent` service principal.
5. **AKS box (Container Apps stand-in).** `rg-ai` → `job-imh-uc-agent` → **Run now** → Execution history →
   Succeeded → Console logs (2–5 min delay): 4 SLC rows, REDACTED names, masked SSNs, HTTP 200. Settings → Identity:
   only `umi-imh-uc-runtime`. Containers → Environment variables: no key.
6. **Foundry Agent Service box + open item 2.** Foundry → `proj-imh-uc-demo` → Agents:
   - `imh-genie-apim-umi-agent`: "How many patients are there per facility? Show the SQL."
   - `imh-uc-limited-agent`: "Show me all patients across every facility." → blocked by the gateway. Then "SLC only"
     → 4 rows. Wait a minute between asks (3 tool calls per minute).

   Then APIM → *IMH UC functions MCP - limited* policy: `rate-limit-by-key calls="3"`, `quota-by-key calls="200"`,
   outbound row count `> 5` → `x-imh-gateway-block`.
7. **APIM logging.** `law-imh-uc-66zpmtcbvhe7w` → Logs:
   `ApiManagementGatewayLogs | where TimeGenerated > ago(4h) | project TimeGenerated, ApiId, ResponseCode, CorrelationId | order by TimeGenerated desc`
8. **⑤ / ⑥ Models.** APIM → *Foundry models (via UMI)* policy: `llm-token-limit` (20k tokens/min) + managed identity
   to Foundry. Then in a normal PowerShell: `cd infra\uc-agent-gateway\databricks; .\Setup-DatabricksSide.ps1` (signs
   in as jay@brakekat.com). Databricks → Serving → `imh-foundry-gpt41-via-apim` → AI Gateway = Yun's Unity AI Gateway.

①, ② and the private parts of ④ and ⑥ have nothing to click; they're talk track (section 6).

## 6. What's different from IMH, and why (say it before they ask)

| Item | BrakeKat | IMH |
|---|---|---|
| Runtime | Container Apps job | AKS + workload identity (AKS provider isn't registered in BrakeKat) |
| Entra audience | `https://management.azure.com` + client allow-list (interim) | App registration `api://imh-uc-gateway`. The guest deploy account couldn't create one (jay@brakekat.com can; section 7), and a managed identity can't be a token audience (AADSTS100040) |
| Network | Public | Private Link + APIM VNet integration (not rebuilt here, to avoid breaking the demo) |
| Front door (①, ②) | None; agents call APIM directly | Cloudflare → App Gateway (WAF) → APIM in internal mode |
| Regions | All in West US 3 | APIM, AKS, Databricks in West US 2; Foundry in East US 2 over VNet peering |
| Identity Databricks sees | APIM managed identity (`imh_analyst`) on the APIM paths | Same, or per-user OAuth (Proof B) when the person must show in Query History |
| Microsoft 365 sign-in (Priority 2) | jay@brakekat.com is a Global Admin and can approve Databricks' Microsoft 365 app himself | IMH's Microsoft 365 admin approves the app and its `.All` scopes; compliance clears Microsoft 365 content (may hold PHI) reaching Databricks |

## 7. Gaps we can still close without networking

| Gap (Yun) | Fix | Who |
|---|---|---|
| ⑥ The runtime isn't an LLM agent yet | Job calls gpt-4.1 through `/aoai` and tools through `/uc-entra` (like Yun's FIT agent) | Agent |
| ③ Foundry agents still use APIM keys | Switch their connections to Entra auth (project managed identity), if Foundry supports it for custom MCP; add it to the allowed-app list | Agent |
| ③ Interim ARM audience | Gateway app registration `api://imh-uc-gateway` (jay@brakekat.com is a global admin), then redeploy | Jay (5 min), then agent |
| ⑤ Databricks side | Run `Setup-DatabricksSide.ps1`, then a Databricks agent that calls through the endpoint | Jay, then agent |
| ① Copilot Studio | Copilot Studio agent calling the APIM MCP endpoint | Needs a Copilot Studio license in BrakeKat |
| AKS itself | Register `Microsoft.ContainerService` on the subscription | Joey (or Jay, if subscription Owner) |
| Priority 1: Genie One MCP | Listed and Active ✅; Genie One chat test ✅ (Oct 13). Next, a Foundry connection to `https://adb-2813105879250022.2.azuredatabricks.net/ai-gateway/mcp-services/system.ai.genie_one_mcp` (per user; new Databricks app connection `foundry-genie-one-imh` with scopes `ai-gateway` + `offline_access`, so Proof B's app `foundry-genie-imh-uc` stays untouched; app changes can take up to 30 min to apply; test users need `EXECUTE` on the MCP); then an APIM API in front of it using the same managed identity (service-principal sign-in is supported; untested here) | Jay (Databricks UI, account console), then agent |
| Priority 2: Databricks → Microsoft 365 | ✅ Oct 13. Genie One chat → **+** (bottom-left of the question box) → Microsoft 365 → **Sign in** as jay@brakekat.com, *Consent on behalf of your organization* unticked. Write ✅: Outlook draft "Patients per Facility Summary" to clinician-slc (Outlook flags the address as not valid because clinician-slc has no mailbox; don't send). Read: empty inbox. Next: send yourself a synthetic question email and have Genie One answer it from UC as a draft reply (read → UC → write). Then register Microsoft Learn MCP; then Work IQ | Jay (Databricks UI, Outlook) |
| Unity Gateway guardrail | Built-in Sensitive Data Detection policy on `genie_one_mcp` blocking `class.us_ssn` | Needs the account-level Unity Gateway beta (account console → Previews), which applies to Joey's whole account: tell Joey, then Jay |
| Priority 2: reverse | Foundry agent with the Work IQ tool + the Genie tool | Needs Work IQ billing in BrakeKat |
| Vector Search (now AI Search) in managed MCP | AI Search index on synthetic notes + MCP | Agent (nice to have) |

## 8. IaC map (what to show if they ask "can we deploy this?")

| Ask | File |
|---|---|
| APIM, APIs, policies, keys, identities, Foundry connections | `azure/bicep/main.bicep` or `azure/terraform/main.tf` |
| Agent runtime | `azure/bicep/runtime.bicep` or `azure/terraform/runtime.tf` |
| Policies | `azure/policy-*.xml` (Terraform reads these; `main.bicep` still has the same XML inline — keep both in sync until the Bicep refactor) |
| Groups, SP, grants, UC objects, model serving endpoint | `databricks/terraform/` (`model_gateway.tf` = Databricks → APIM → Foundry) |
| Agents | `foundry/create_agents.py --kind uc|genie --ask "..."` |

**Status:** Bicep is what's deployed and tested. The Terraform hasn't had `terraform validate` run yet (a local tooling
outage stopped the run). Do that first if you want to say "Terraform works".
