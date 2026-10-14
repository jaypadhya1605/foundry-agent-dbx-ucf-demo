# Dry-run agent: IMH onsite, Option 2 (UC Functions + MCP + API Management)

**How to start a new chat:** open VS Code in the `On site -- Foundry and Databricks Session` folder (the parent of
`JAY DEMO v2`; every path and command below is relative to it) and say:
*"Read `JAY DEMO v2\dry-run-agent.md` and run my dry run, one step at a time."*

Onsite: **Thursday 2026-10-15**, Intermountain Health (IMH). Jay lands ~10:15 and is in the room ~11:00.
Demo slots: **11:00–12:00** (Jay + Joey) and **3:00–3:30** (Foundry end-to-end).
Reading copy and in-room fallback: [IMH-Option2-Dry-Run-and-Workflow.docx](./IMH-Option2-Dry-Run-and-Workflow.docx).
Everything below was re-verified live on **Oct 14, 2:05–2:45 PM ET**.

---

## 0. Rules for you (the dry-run agent)

1. Jay is the presenter and says he is **confused about the concepts**. Coach him. Before each step, explain the idea
   in **3 lines or fewer** in plain English and name its place on Yun's diagram (①–⑥). After the step, ask him **one**
   check question.
2. **One step at a time.** Give: **Open → Do → Expect → Say → If it fails.** Jay clicks, then replies "done" or pastes a
   screenshot. Compare what he sees with **Expect**. Wait for him before moving on.
3. Have Jay **say the "Say" lines out loud** (or type them). Tighten his wording; never make it longer.
4. Be terse. No preamble, no recap.
5. The shell works (`az`, `databricks`, `python`, `node`). You may run the read-only checks in section 12.
   **Never print, log or write keys or passwords.** Keys go only into `$env:` variables.
6. **Don't change** Foundry agents, APIM, Databricks objects or networking without Jay's explicit OK.
   **Never toggle External Data Access live.** Never create certificate or key files.
7. After each step, append one row to `JAY DEMO v2\dry-run-log.md` (create it if missing):
   `| time | step | pass/fail | note |`.
8. Screenshots Jay pastes are saved under `%APPDATA%\Code\agentSessionData\<session-id>\attachments\`. Copy the good
   ones to `JAY DEMO v2\images\evidence\NN-<step>-<what>.png` (PNG only). Skip any that show a key, secret or password.
   Then rebuild the Word doc (section 13).
9. MSX: log nothing.
10. Scope is **Option 2 only**. Per-user OAuth agents (segments A, B, K) and Genie-through-APIM (G) were deleted from
    Foundry on Oct 14. They are talk track only, with evidence in
    `Jay DEMO\evidence\brakekat-uc-proof\README.md`.

---

## 1. What tomorrow has to prove

IMH's **Scope and Priorities** (from Yun's slide):

1. **Connect Microsoft agents to Databricks tools** (Genie One MCP, Genie agents, UC functions…).
2. **Connect Databricks agents with Work IQ, Microsoft Graph and other Microsoft MCP services, in both directions.**

**The one-line answer for Mark:** an Azure agent can query Databricks **through Unity Catalog, with Unity Catalog as the
only governance layer**, using **Azure agent → APIM → MCP server → UC function → Databricks tables**. It does **not**
need External Data Access, because the function runs inside Databricks.

| Priority | What we show | Proof |
|---|---|---|
| 1 | Foundry agent → APIM → Databricks MCP → UC function, with gateway guardrails | C, H, D, E: live |
| 1 | Custom runtime (AKS stand-in) → APIM with an Entra token, no key | I: live |
| 2 | Databricks → APIM → Foundry model (`ai_query`) | J: live |
| 2 | Databricks agent (Genie One) → Microsoft 365 → Outlook draft | Screenshots (Oct 13) |

**Context from IMH (frame it this way):**
- **Which project?** Mark: not one project. **Ventures** is the clearest case for Microsoft agents needing Databricks
  MCP tools; a handful of others benefit from Microsoft MCP tools offered to Databricks agents.
- **What Mark asked for:** Unity Catalog as the only governance layer (no second layer in Fabric). If External Data
  Access doesn't make sense, pivot to Unity Gateway / APIM / Foundry integrations. That is Option 2.
- **What IMH already has:** Brian's team runs an Azure agents control plane: APIM + AKS, user-assigned managed
  identities, Agents 365 kill switch. Option 2 plugs into it.
- **Tony Sargent's call** (per Chris): getting Databricks data into Azure agents through APIM / MCP calls to Databricks
  APIs. Same pattern.

## 2. The story in one breath (Jay memorizes this)

> "Your agents, Foundry today and AKS tomorrow, call Databricks through APIM. APIM is the Microsoft-side gate: who may
> call, how often, how much comes back, and a log of every call. Behind it, Databricks exposes Unity Catalog functions
> as MCP tools, and Unity Catalog alone decides which rows and columns come back. No External Data Access, no copy of
> the data, and no secret between APIM and Databricks."

**Two gateways, one decider:** APIM (Microsoft side) and Unity Gateway (Databricks side, for new builds) control
access. **Unity Catalog decides the data.**

## 3. Concepts Jay must own (teach these first, 1 minute each)

| Term | Plain English | Where he'll see it |
|---|---|---|
| **MCP** | A standard way for an agent to list tools (`tools/list`) and call them (`tools/call`) over HTTPS. Like USB-C for agent tools | Foundry agent's tool; APIM logs |
| **UC function** | A SQL function saved in Unity Catalog. `get_patients(fac)` is a pre-written query; the agent fills in `fac` but can't change the SQL | Catalog → `imh_demo.clinical` → Functions |
| **Databricks managed MCP server** | Databricks hosts the MCP endpoint. Every table function in a schema becomes a tool: `/api/2.0/mcp/functions/imh_demo/clinical` | APIM backend URL |
| **Unity Catalog row filter / column mask** | Rules checked for whoever runs the query: the filter decides rows (facility), masks decide what `name` and `ssn` show | Table `patients` → Overview |
| **APIM** | Azure API Management, the Microsoft-side gateway: checks the caller (key or Entra token), applies policies (rate, quota, row cap), signs in to Databricks, logs every call | Azure portal → APIM → APIs |
| **Managed identity (UMI)** | An Entra identity for an Azure resource. No password or secret; Azure issues its tokens | `umi-imh-uc-agent` (APIM → Databricks) and `umi-imh-uc-runtime` (job → APIM) |
| **Service principal + OAuth M2M** | The managed identity is registered in Databricks as a non-human user in group `imh_analyst`. APIM signs in **as itself**, not as the caregiver (Yun ④) | Databricks → Groups → `imh_analyst` |
| **Tool allow-list** | The agent may call only `imh_demo__clinical__get_patients` | Agent definition |
| **External Data Access (EDA)** | A metastore switch that lets outside engines read UC storage directly. Not needed here | Metastore settings (screenshot) |
| **Serverless compute** | Databricks-managed compute that runs the MCP function calls. First call is ~20 s cold | Query History "serverless" |
| **Unity Gateway** | Databricks' new (Oct 2026) gateway for MCP and models: grants, policies and tracing per MCP. Our APIM path uses the *legacy* MCP URL, which bypasses it | AI/ML → AI Gateway |

**Four layers, one sentence each** (the answer to "what stops an agent from pulling everything?"):

1. **Agent allow-list** picks the tool.
2. **UC function** fixes the query (no free-form SQL).
3. **APIM** limits who, how often and how much (5 rows / 20 KB on `/uc-limited`, 3 tool calls a minute, 200 a day).
4. **Unity Catalog** decides rows and columns for the identity that runs it.

## 4. Yun's diagram → what we show

Images: `images\01-yun-architecture.png` (diagram), `images\02-yun-open-items.png`, `images\03-option2-slide.png`.

| Yun | Box | What we show | Status |
|---|---|---|---|
| ① | Teams / M365 Copilot / Copilot Studio (Entra sign-in) | Not built | ❌ talk track |
| ② | Cloudflare → App Gateway (WAF) | Not built (networking) | ❌ talk track |
| Runtime | Agent Runtime: AKS | Container Apps job `job-imh-uc-agent` with its own managed identity (step 10) | 🟡 stand-in |
| Runtime | Foundry Agent Service | Agents C and H (steps 6–7) | ✅ |
| ③ | APIM validates the Entra token, applies policy, routes to the MCP tool | `/uc-entra` (token + allowed-app list, 401 otherwise); `/uc`, `/uc-limited` (key + limits) | ✅ (interim audience) |
| ④ | APIM → Databricks managed MCP / UC, OAuth M2M via Entra | APIM signs in as `umi-imh-uc-agent` = service principal in `imh_analyst` | ✅ identity, ❌ private network |
| UC | Unity Catalog governs access | Row filter + masks on `imh_demo.clinical.patients` | ✅ |
| ⑤ | Databricks → Unity AI Gateway → APIM → Foundry models | Endpoint `imh-foundry-gpt41-via-apim` → APIM `/aoai` → gpt-4.1 (step 11) | ✅ |
| ⑥ | AKS / APIM → Foundry models over private endpoint | `/aoai` over public network | 🟡 |
| Open item | APIM ↔ Databricks serverless connectivity (DMZ) | Identity proven; network not built (Private Link one way, NCC the other) | talk track |
| Open item | Result-size / row limits via APIM MCP | `/uc-limited` (step 7) | ✅ |
| Open item | AKS as the standard runtime | Same client in Container Apps; on AKS only the sign-in changes (workload identity) | 🟡 |
| Open item | Foundry public DNS limitation → runtime on AKS | Both runtimes call the same governed APIM tool | ✅ |

**Option 2 slide** (`images\03`): "Azure Agent → APIM → MCP Server → UC Function → Databricks Tables". Its examples
(`get_patient_demographics`, `get_claim_history`, `get_authorization_status`) = our `get_patients(fac)` and
`get_patients_limited(fac, max_rows)`. Best fit per the slide: deterministic workflows, controlled inputs and outputs,
reuse across Foundry / M365 Copilot / other platforms, central API policy and monitoring.

## 5. What's live after the Oct 14 cleanup

**Foundry** `aif-wu3` → project `proj-imh-uc-demo` (gpt-4.1):

| Agent | Version | Tool connection → APIM route | Step |
|---|---|---|---|
| `imh-uc-apim-umi-agent` (C) | **v6** | `uc-fn-via-apim-umi` (APIM key) → `/uc/mcp` | 6 |
| `imh-uc-limited-agent` (H) | **v3** | `uc-limited-via-apim-umi-iac` (APIM key) → `/uc-limited/mcp` | 7 |

Both: allow-list `imh_demo__clinical__get_patients`, no approval prompt, and "leave `fac` out for all facilities".
Deleted Oct 14: agents A, B, G, K and their 3 OAuth tools (snapshot: `JAY DEMO v2\evidence\foundry-agents-before-cleanup.json`).
Joey's connections (`CMS-Data-Agent-Connection`, `aif-rjb-eu2`, `CRM-AgentSkill`, `FabricPowerBIMCP`): never touch.

**APIM** `apim-imh-uc-66zpmtcbvhe7w` (BasicV2, West US 3), `https://apim-imh-uc-66zpmtcbvhe7w.azure-api.net`:

| Route | API name in portal | Caller proves itself with | Policy | Backend |
|---|---|---|---|---|
| `/uc` | IMH UC functions MCP (via UMI) | key, subscription `foundry-imh-uc-agent` | rate limit, managed identity to Databricks | Databricks `/api/2.0/mcp/functions/imh_demo/clinical` |
| `/uc-limited` | IMH UC functions MCP - limited (rate, quota, size cap) | key, `imh-uc-limited-client` | 3 tool calls/min, 200/day, >5 rows or >20 KB → MCP error + `x-imh-gateway-block` | same |
| `/uc-entra` | IMH UC functions MCP - Entra token (no key) | Entra token; only the runtime's app ID is allowed | 401 for anyone else | same |
| `/aoai` | Foundry models (via UMI) | key, `databricks-ai-gateway` | `llm-token-limit` 20k tokens/min, managed identity to Foundry | `aif-wu3` gpt-4.1 |
| `/genie` | IMH Genie space MCP (via UMI) | key | not shown tomorrow | Genie space |

The portal also lists two **"HLS imaging"** APIs (`/hls-genie`, `/hls-uc`, pointing at another workspace), and `rg-ai`
has two Container Apps jobs `job-hls-genie-mcp-demo` / `job-hls-uc-mcp-demo` (created Oct 13, 20:45 UTC). Not ours,
not part of this demo: don't open or run them.

**Identities:** `umi-imh-uc-agent` (client ID `e983157d-68fc-430a-9ee8-cdf1efe4b68e`; APIM → Databricks; in
`imh_analyst`). `umi-imh-uc-runtime` (job → APIM `/uc-entra`).
**Runtime:** Container Apps job `job-imh-uc-agent` (rg `rg-ai`, manual trigger, `APIM_AUTH=mi`).
**Logs:** Log Analytics `law-imh-uc-66zpmtcbvhe7w` (workspace ID `abf8c64e-99ad-4faf-b61b-fac726ddee36`).

**Databricks** `adb-rjb-wu3`, `https://adb-2813105879250022.2.azuredatabricks.net`, metastore `metastore_azure_westus3`:

- Table `imh_demo.clinical.patients`: 12 synthetic rows (SLC 4, OGDEN 3, PROVO 3, STGEORGE 2).
- Rules: row filter `fac_filter`; masks `mask_ssn`, `mask_name`.
- Tools: `get_patients(fac)`, `get_patients_limited(fac, max_rows)` (Unity Catalog caps it at 10 rows).
- Groups: `imh_phi_full` (jay: everything), `imh_clinician_slc` (SLC only, names shown, SSN masked),
  `imh_analyst` (all rows, names `REDACTED`, SSN masked; **the APIM identity is here**).
- Warehouse `adb-demo-wh` (serverless; SQL editor, Genie and `ai_query` only). **MCP calls run on serverless compute,
  not on this warehouse.**
- Serving endpoint `imh-foundry-gpt41-via-apim` (AI Gateway: usage tracking, 60 calls/min; APIM key in secret scope
  `imh-apim`).
- Genie One + Microsoft 365 connector (Jay signed in Oct 13): Priority 2 backup.

## 6. Pre-flight

**Today's dry run:** Edge only. Sign in to Foundry and Databricks as `jay@brakekat.com`; Azure portal in the
**BrakeKat** directory with the account that owns `rg-ai` (jaypadhya@microsoft.com guest; `jay@brakekat.com` opened
Log Analytics on Oct 12, image 12). Option 2 needs **no** per-user browsers.

**Tabs, in this order:**

1. `images\01-yun-architecture.png`, `images\03-option2-slide.png`
2. Databricks table: `https://adb-2813105879250022.2.azuredatabricks.net/explore/data/imh_demo/clinical/patients?o=2813105879250022`
3. Databricks → Settings → Identity and access → Groups → `imh_analyst`
4. Azure portal → `apim-imh-uc-66zpmtcbvhe7w` → APIs
5. Agent C: `https://ai.azure.com/nextgen/r/m77hkNxhTFirRxJ1ywQBjw,rg-ai,,aif-wu3,proj-imh-uc-demo/build/agents/imh-uc-apim-umi-agent/build?tid=8d038e6a-9b7d-4cb8-bbcf-e84dff156478`
6. Agent H: same link with `imh-uc-limited-agent`
7. Databricks Query History: `https://adb-2813105879250022.2.azuredatabricks.net/sql/history?o=2813105879250022&preset=d_last_hour`
8. Log Analytics `law-imh-uc-66zpmtcbvhe7w` → Logs, with the KQL from section 12 pasted
9. Azure portal → Container Apps job `job-imh-uc-agent`
10. Databricks Serving → `imh-foundry-gpt41-via-apim`, plus SQL editor on `adb-demo-wh` with the two queries from step 11
11. `images\17`–`19` (Priority 2)
12. The Word doc (fallback)

**Warm-ups (10 minutes before):**

- Agent C: "Show me patients at SLC." (wakes serverless; ~20 s cold, ~7 s warm).
- SQL Warehouses → `adb-demo-wh` → **Start** (only for step 11).
- Start the job ~3 minutes before step 10 (logs take 1–5 minutes to appear).
- Don't use agent H in the minute before the demo (3 tool calls per minute).
- In each agent, check the version picker shows C **v6** / H **v3** (refresh first; v3 is the version whose tool shows in the Tools panel).

**Tomorrow:** Jay arrives at 11:00. Do the warm-ups from the car at ~10:45 (phone hotspot), or ask Joey to run agent C
once and start `adb-demo-wh`. Joey opens with the Databricks side (10 min), so steps 3–4 may already be covered.

## 7. The dry run (11:00–12:00 block, ~45 minutes)

### Step 1. Frame it on Yun's diagram (3 min). Yun: all
- **Open:** `images\01-yun-architecture.png`.
- **Say:** "Your two priorities are Microsoft agents using Databricks tools, and Databricks agents using Microsoft
  services. On Yun's diagram I'll walk the middle path: an agent calls APIM, APIM calls Databricks as a managed
  identity, and Unity Catalog decides what comes back. That's ③ and ④. Then ⑤: Databricks calling a Foundry model
  through the same APIM."
- **Concept check:** "Which component decides which rows come back?" (Unity Catalog.)

### Step 2. Option 2 slide (2 min)
- **Open:** `images\03-option2-slide.png`.
- **Say:** "Option 2 is exactly what's running: Azure agent, APIM, MCP server, UC function, tables. The tools are
  Unity Catalog functions, so the agent can only run queries we wrote and fill in parameters. No free-form SQL. Your
  slide's examples were get_patient_demographics or get_claim_history; ours is get_patients by facility."

### Step 3. The rules live in Unity Catalog (4 min). Yun: "Unity Catalog governs access"
- **Open:** tab 2 (table `patients`) → Overview shows the row filter and column masks; then the schema → Functions.
- **Expect:** row filter `fac_filter`; masks on `name` and `ssn`; functions `get_patients`, `get_patients_limited`.
- **Say:** "This is synthetic data: 12 patients in 4 facilities. Unity Catalog has three rules on this table: a row
  filter by facility, and masks on name and SSN. They're checked for whoever runs the query, every time. The agent's
  tool is this function, get_patients. It runs inside Databricks, so the rules always apply."
- **If Joey already showed it:** "As Joey showed, the rules sit on the table," then go to step 4.

### Step 4. Who Databricks thinks is calling (2 min). Yun ④
- **Open:** tab 3 (`imh_analyst` → Members).
- **Expect:** `umi-imh-uc-agent`.
- **Say:** "APIM signs in to Databricks as this managed identity: an Entra identity with no password or secret. In
  Databricks it's a service principal in the analyst group, so every call through APIM gets analyst rules: all
  facilities, names redacted, SSNs masked. That's Yun's ④, machine-to-machine sign-in through Entra."

### Step 5. The gateway policy (3 min). Yun ③ → ④
- **Open:** tab 4 → *IMH UC functions MCP (via UMI)* → All operations → Inbound processing → `</>`.
- **Expect:** `rate-limit-by-key`, two `set-header … delete`, `rewrite-uri`, `authentication-managed-identity`.
- **Say:** "This is the Microsoft-side gate. It rate-limits each caller, strips the caller's key so it never reaches
  Databricks, forwards to the Databricks MCP server for imh_demo.clinical, and gets an Entra token for Databricks as
  the managed identity. Nothing secret is stored in the policy."

### Step 6. Segment C live: Foundry agent → APIM → UC function (6 min). Foundry box → ③ → ④ → UC
- **Open:** tab 5 (agent C, v6).
- **Ask:** "Show me patients at SLC."
- **Expect:** tool call `imh_demo__clinical__get_patients` with `{"fac":"SLC"}`; 4 rows P001–P004, names `REDACTED`,
  SSN `***-**-1001` to `***-**-1004`; ~7 s warm, ~20 s cold.
- **Ask:** "Show me all patients."
- **Expect:** `get_patients` with `{}`; 12 rows across SLC, OGDEN, PROVO and STGEORGE, all masked.
- **Say:** "The agent chose the get_patients tool and filled in the facility. The call went to APIM, APIM called
  Databricks as the managed identity, and Unity Catalog applied the analyst rules, which is why names say REDACTED.
  Nobody signed in to Databricks, and the agent never held a Databricks credential."
- **If it fails:** slow → cold serverless, wait 30 s and ask again. Approval prompt → wrong version selected (pick
  v6) or click Approve. 0 rows → check the tool call arguments; run the script check (section 12) and show
  `images\10`.

### Step 7. Segment H: gateway guardrails (5 min). Open item: result-size / row limits
- **Open:** tab 6 (agent H, v3).
- **Ask:** "Show me all patients across every facility."
- **Expect:** blocked. The gateway's text: *"Blocked by gateway policy: the result has 12 rows (limit 5) or is larger
  than 20000 bytes. Ask a narrower question, for example one facility."* Foundry shows it as a tool error, or the agent
  rewords it and suggests one facility. **Both are a pass.**
- **Ask:** "OK, just SLC then." → 4 rows.
- **Say:** "Same identity, same data, different APIM route. This one has guardrails: more than 5 rows or 20 KB comes
  back as an error, 3 tool calls a minute, 200 a day. APIM doesn't know your PHI rules and shouldn't; Unity Catalog
  still decides the rows. APIM limits the blast radius. That's your open item on result-size limits."
- **Add (layers):** "In testing, an agent picked the wrong function, so the agent now has an allow-list too. The
  allow-list picks the tool, the function fixes the query, APIM limits volume, and Unity Catalog decides rows and
  columns."
- **Optional 429:** ask 4 SLC questions inside a minute; the 4th gets "Rate limit is exceeded". Say: "That's the
  rate limit doing its job."
- **If it isn't blocked:** the agent sent a facility. Ask again: "All facilities, no filter." Or run the script check.

### Step 8. Segment D: the audit trail (5 min)
- **Open:** tab 7 (Query History, last hour). Filter **User** = `umi-imh-uc-agent` if the list is busy.
- **Expect:** ``SELECT * FROM `imh_demo`.`clinical`.`get_patients`(fac => "SLC")``, User `umi-imh-uc-agent`, Source
  *Spark Connect API*, Compute *Serverless compute for Notebooks* (not `adb-demo-wh`).
- **Open:** tab 8 (Log Analytics) → run the KQL.
- **Expect:** rows for `imh-uc-functions-mcp` and `imh-uc-functions-mcp-limited`: POST 200, POST 202, GET 405, with
  ApimSubscriptionId and CorrelationId.
- **Say:** "Both sides keep a record. Databricks shows the exact SQL the tool ran and that it ran as the agent
  identity. APIM shows which subscription called, the response and a correlation ID. A blocked result still logs 200
  in APIM, because the block comes back as an MCP error inside a normal response."
- **Concept:** POST 202 = MCP notification. GET 405 = the client asks for a stream and Databricks declines (harmless).
- **If empty:** APIM logs lag 2–5 min, so widen to `ago(24h)`. Show `images\11` and `images\12`.

### Step 9. Segment E: no External Data Access (1 min). Screenshots only
- **Open:** `images\13-segment-e-eda-disabled.png`, `images\14-segment-e-agent-works-with-eda-off.png`.
- **Say:** "External Data Access lets outside engines read Unity Catalog storage directly. We turned it off on
  October 12 and the agent still worked, because the function runs inside Databricks. Fabric mirroring is the path
  that needs it, and that's out of scope."
- **Never toggle EDA live** (it's Joey's metastore).

### Step 10. Segment I: custom runtime, Entra token, no key (4 min). Yun ③ + AKS box
- **Open:** tab 9 → **Run now** (~3 min earlier) → Execution history → latest → Console logs.
- **Expect:** `# url=…/uc-entra/mcp auth=mi`, `initialize: HTTP 200`,
  `tools: ['imh_demo__clinical__get_patients', 'imh_demo__clinical__get_patients_limited']`, `tools/call: HTTP 200`,
  then 4 SLC rows, masked. Today's run took 39 s; logs appeared within about 2 minutes.
- **Optional:** you (agent) run the 401 check in section 12 and show Jay the output.
- **Say:** "This stands in for your AKS pod: a Python client with its own managed identity and no key in the
  container. APIM validates its Entra token: right tenant, right audience, and its app ID is on the allow-list. My own
  token gets a 401 because I'm not on the list. On AKS it's the same code with workload identity."

### Step 11. Segment J: Databricks → APIM → Foundry model (4 min). Yun ⑤ (⑥ public here). Priority 2
- **Open:** tab 10: Serving → `imh-foundry-gpt41-via-apim` (AI Gateway: usage tracking, 60 calls/min), then the SQL editor.
- **Run:** `SELECT ai_query('imh-foundry-gpt41-via-apim', 'In one sentence, what does Unity Catalog govern?') AS answer;`
- **Expect:** a one-sentence answer (~18 s if the warehouse starts).
- **Run:** `SELECT count(*) AS rows_returned FROM imh_demo.clinical.get_patients_limited(NULL, 50);` → **10**.
  Use `count(*)` in the room: as jay (`imh_phi_full`) the rows show full synthetic names and SSN-like values.
- **Say:** "Now the other direction, Yun's ⑤: Databricks calling a Foundry model. The serving endpoint points at our
  APIM, not straight at Foundry. APIM applies a token limit and signs in to Foundry with a managed identity, and
  Databricks' AI Gateway adds its own usage tracking and rate limit. And Unity Catalog can cap rows itself: I asked
  this function for 50 and got 10."

### Step 12. Priority 2: a Databricks agent writes to Microsoft 365 (3 min). Screenshots
- **Open:** `images\17-genie-one-patients-per-facility.png`, `images\18-priority2-genie-one-drafts-email.png`,
  `images\19-priority2-outlook-draft.png`.
- **Say:** "Your second priority is Databricks agents working with Microsoft services. Databricks' own agent, Genie
  One, answered from Unity Catalog and then drafted this Outlook email through Databricks' built-in Microsoft 365
  connector, signed in as me. No app registration, no code. Work IQ is next: it needs Copilot licensing, and cyber has
  to clear PHI leaving the Azure boundary. The reverse direction, Copilot Studio or Teams calling Databricks, is ① on
  Yun's diagram and isn't built."

### Step 13. Limitations and this afternoon (3 min)
- **Say:** "Three things to be clear about. One: this is our demo tenant with synthetic data on public endpoints. The
  private network isn't built: Private Link from APIM to Databricks, and NCC for serverless back to APIM. Two: on this
  path Databricks sees the agent's identity, not the caregiver's. That's Yun's design for ④; per-user sign-in works
  too, and we proved it separately. Three: we call Databricks' legacy MCP endpoint. For a new build, point APIM at the
  Unity Gateway URL so both gateways apply. This afternoon in your sandbox we can stand up the same pattern: one UC
  function, APIM's identity as a service principal, and one APIM API."

**After step 13:** run the Q&A drill (section 9).

## 8. 3:00–3:30 Foundry end-to-end (dry run ~20 minutes)

1. **Foundry project tour (5):** agents C and H → Tools: MCP tool → connection (APIM key), model gpt-4.1, allow-list.
   Say: "The agent is a prompt, a model and one tool. The tool is just an MCP URL on APIM and a key in a project
   connection, which you can swap for an Entra token."
2. **Policies side by side (8):** `/uc` (key + managed identity), `/uc-limited` (rate, quota, row/size cap: show the
   outbound `rowCount > 5` block), `/uc-entra` (`validate-azure-ad-token` with `client-application-ids`). Source
   files: `infra\uc-agent-gateway\azure\policy-mcp-key.xml`, `policy-mcp-limited.xml`, `policy-mcp-entra.xml`.
   Say: "Three routes, one Databricks backend. The first checks a key and signs in to Databricks as the managed
   identity. The second adds rate, quota and a row and size cap on the way out. The third takes no key at all: only an
   Entra token from an app on its list. Your control plane picks the route for each agent."
3. **One call traced (5):** Foundry chat → APIM log (CorrelationId) → Databricks Query History (identity + SQL).
   Say: "One question, three records that tell the same story: Foundry shows the tool call, APIM shows the caller and
   a correlation ID, and Databricks shows the exact SQL and the identity that ran it."
4. **Infrastructure as code (7):** `infra\uc-agent-gateway\`:
   - Bicep: deployed and tested in BrakeKat.
   - Terraform (Azure + Databricks): written, `terraform validate` not run yet.
   - `databricks\Setup-DatabricksSide.ps1`: ran Oct 13.
   - `foundry\create_agents.py`: new `--allowed-tools`.
   - `clients\python_mcp_client.py`: smoke tests.
   Say: "Everything you saw is in this folder. IMH changes the parameters: tenant, workspace, catalog and schema,
   groups, and the gateway's app ID."
5. **Sandbox results (5):** whatever the 1:15–3:00 hands-on produced.

## 9. Q&A drill (agent: ask Jay 8 of these, one at a time; grade him against the answer)

| Question | Answer (say it in under 20 seconds) |
|---|---|
| Do we need External Data Access? | No. The function runs inside Databricks. We proved it with EDA off. Fabric mirroring is the path that needs it |
| Who decides what the agent sees? | Unity Catalog, always. APIM controls who calls, how often and how much comes back, and logs it |
| Does Databricks know which caregiver asked? | Not on this path: it sees the agent identity (Yun ④, M2M). Per-user is the OAuth passthrough path, proven separately; it needs Foundry and Databricks in the same Entra tenant |
| Why APIM if Unity Catalog already governs? | One Microsoft-side gate for every agent platform (Foundry, AKS, Copilot Studio): Entra or key auth, rate limits, quotas, result caps, logs and a kill switch, without touching Databricks |
| What stops an agent pulling the whole table? | Four layers: agent allow-list, fixed UC function, APIM row/size cap and rate limit, Unity Catalog rules. Unity Catalog can also cap rows itself (`get_patients_limited`) |
| Where are the secrets? | None between APIM and Databricks (managed identity). Foundry → APIM uses an APIM key stored in the Foundry connection; the AKS path uses an Entra token, no key |
| Private networking? | Not built here. APIM → Databricks needs Private Link; serverless → APIM needs NCC. Foundry Agent Service resolves tools over public DNS, which is why Yun puts the runtime on AKS |
| Which Databricks MCP endpoint? | Today the legacy `/api/2.0/mcp/functions/<catalog>/<schema>`. New builds: Unity Gateway `/ai-gateway/mcp-services/…` for MCP grants, policies and tracing. The Genie One beta endpoint sunsets Oct 31, 2026; not used |
| What compute runs the tool? | Databricks serverless (first call ~20 s cold). IMH must allow serverless in the workspace |
| How do we audit one call? | APIM log (subscription, CorrelationId) + Query History (exact SQL, identity) + Foundry trace. Can feed Sentinel or `system.access.audit` |
| How do we add a tool? | Write a table function in the schema and grant EXECUTE. It shows up in `tools/list`; add it to the agent's allow-list |
| Kill switch? | Disable the APIM subscription or remove the client from the allowed list (instant); remove the service principal from the group; disable the managed identity. Entra Agent ID / Agents 365 is the enterprise version (talk track) |
| Work IQ? | Needs M365 Copilot licences or pay-as-you-go credits; data can leave the Azure compliance boundary, so cyber has to clear PHI |
| Can we deploy it as code? | Yes: `infra/uc-agent-gateway` (Bicep tested; Terraform written; Databricks setup script; agent script) |
| Is this IMH-ready? | The pattern is. IMH adds its tenant, Private Link/NCC, AKS workload identity, the gateway app registration `api://imh-uc-gateway`, and cyber sign-off for MCP on `apim-ih-ent-eap-dev` |
| Which IMH project is this for? | Not one project. Mark named Ventures as the clearest case for Microsoft agents using Databricks tools; others benefit from Microsoft MCP tools in Databricks agents |
| Does it fit what Brian's team built? | Yes. Their control plane is APIM + AKS with managed identities and an Agents 365 kill switch. Option 2 adds one APIM API per UC schema and one service principal in Databricks |

## 10. Not built (say it before they ask)

- ① Copilot Studio / Teams → Databricks; ② Cloudflare → App Gateway.
- Private network: Private Link (APIM → Databricks), NCC (serverless → APIM), VNet peering, West US 2 + East US 2.
- AKS: a Container Apps job stands in (the AKS provider isn't registered in BrakeKat).
- Gateway app registration: interim audience is ARM (`https://management.azure.com`) + client allow-list.
- APIM → Unity Gateway MCP URL: untested (legacy endpoints are proven).
- Work IQ; Microsoft Learn MCP; a custom Databricks agent on the `/aoai` endpoint.
- `terraform validate` not run.

| Item | BrakeKat demo | IMH |
|---|---|---|
| Tenant / data | Joey's demo tenant, 12 synthetic rows | IMH tenant, real data |
| Runtime | Container Apps job | AKS + workload identity |
| Entra audience | ARM + allowed-app list | `api://imh-uc-gateway` |
| Network | Public | Private Link + APIM VNet integration |
| Front door | None | Cloudflare → App Gateway (WAF) → internal APIM |
| Regions | West US 3 | West US 2 + East US 2, peered |
| APIM → Databricks MCP | Working | `apim-ih-ent-eap-dev` has Databricks REST only; MCP in cyber review (Yun, Oct 14) |

**IMH sandbox for the 1:15–3:00 hands-on:** `https://adb-7405605832508369.9.azuredatabricks.net` (Peter Jones; group
`DPG_FOUNDRY_CONNECTION_TEST`). Checklist: Managed MCP enabled; serverless allowed; a non-PHI table; one UC table
function; APIM's managed identity added as a service principal with USE CATALOG / USE SCHEMA / EXECUTE / SELECT; APIM
API → `/api/2.0/mcp/functions/<catalog>/<schema>` with `policy-mcp-key.xml`; test with `python_mcp_client.py`.

## 11. If something breaks

| Symptom | Fix | Fallback |
|---|---|---|
| First agent answer takes 20+ s | Serverless cold start. Talk through step 5 while it runs | — |
| Approval prompt in C or H | An old version is selected; pick C v6 / H v3, or click Approve | — |
| H's Tools panel is empty | H v2 is selected (it references its connection by full ID, so the UI hides the tool); pick H v3 | Chat still works on v2; show the YAML tab |
| C returns 0 rows | Check the tool-call arguments (should be `{"fac":"SLC"}` or `{}`) | `images\10` + script check |
| H returns rows for "all" | The agent sent a facility. Ask "All facilities, no filter" | Script check with `--args '{}'` |
| 429 on H | Rate limit (3 tool calls/min). Wait 60 s and say "that's the limit working" | — |
| Query History empty | Widen the time range; clear the Compute filter (MCP calls run on serverless, not `adb-demo-wh`) | `images\11` |
| APIM logs empty | Ingestion lag 2–5 min; widen to `ago(24h)` | `images\12` |
| Job logs empty | Lag 1–5 min; show the previous run | Run section 12 command and show its output |
| `ai_query` error | Start `adb-demo-wh`; check the endpoint is READY | `images\15` |
| Foundry opens the wrong tenant | Use the deep link with `?tid=8d038e6a-9b7d-4cb8-bbcf-e84dff156478` | — |
| Everything is down | Open the Word doc and walk sections 7–8 | Screenshots |

If a live step fails twice, show its screenshot and move on. Words for it: "That's serverless waking up, which is a
real thing you'll see in production too. While it runs, here's what it's doing." or "Let me show you a recorded run
instead; it's the same call and the same rules."

## 12. Commands you (the agent) can run

Read-only except the job start. Keys stay in `$env:`; never echo them.

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

The Databricks CLI profile `brakekat` signs in as `jay@brakekat.com`. `az` is on subscription `Azure-brakekat`
(`9bbee190-dc61-4c58-ab47-1275cb04018f`), tenant `8d038e6a-9b7d-4cb8-bbcf-e84dff156478`.

KQL for tab 8:

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(4h)
| project TimeGenerated, ApiId, Method, ResponseCode, ApimSubscriptionId, CorrelationId, BackendUrl
| order by TimeGenerated desc
```

## 13. Log, evidence, Word doc

- Log every step in `JAY DEMO v2\dry-run-log.md`.
- Screenshots → `JAY DEMO v2\images\evidence\NN-<step>-<what>.png`.
- Rebuild the Word doc (close it in Word first; run from the `On site -- Foundry and Databricks Session` folder):
  `node "JAY DEMO v2\build\build-docx.mjs"`, then validate:
  `$env:PYTHONUTF8='1'; python "$env:USERPROFILE\.copilot\skills\docx\scripts\office\validate.py" "JAY DEMO v2\IMH-Option2-Dry-Run-and-Workflow.docx"`.
  To change the text, edit `JAY DEMO v2\build\content\*.md` (one file per section), not the .docx.
  Every PNG in `images\evidence\` is added to the "Evidence from the dry run" section.
- At the end, give Jay: what failed and the fix, and the **5 lines to remember** (section 2 story, four layers,
  EDA not needed, identity is the agent's, what's not built).
- MSX: nothing during the dry run. After the onsite, and only with Jay's OK, log the activity on the **milestone** under
  opportunity **7-3HFNQXLBBY** (FY27 | Intermountain | AI Agent Landing Zone), never on the opportunity itself.

## 14. File index

| File | Use |
|---|---|
| `JAY DEMO v2\IMH-Option2-Dry-Run-and-Workflow.docx` | Flight reading + in-room fallback |
| `JAY DEMO v2\images\01`–`19` | Diagram, slide and proof screenshots (05 and 06 removed: IMH Teams content) |
| `JAY DEMO v2\build\build-docx.mjs` | Rebuilds the Word doc |
| `JAY DEMO v2\build\content\*.md` | The Word doc's text, one file per section |
| `JAY DEMO v2\dry-run-log.md` | Step log written during the dry run |
| `JAY DEMO v2\evidence\foundry-agents-before-cleanup.json` | Agent definitions before the Oct 14 cleanup |
| `Jay DEMO\claude-imh-dbx-foundry-demo.md` | Full demo record (segments A–K, questions for IMH) |
| `Jay DEMO\learn-tomorrow-must-should-build.md` | Yun mapping and learning route |
| `Jay DEMO\IMH-thread-and-control-plane-context.md` | People and the IMH thread |
| `Jay DEMO\evidence\brakekat-uc-proof\README.md` | Proof record, including the Oct 14 re-test |
| `infra\uc-agent-gateway\` | IaC, policies, smoke client, agent script |
| `JAY DEMO v2\resources\` | Older Oct 13 copies; not the source of truth. One file holds plaintext credentials: move them to a vault |
