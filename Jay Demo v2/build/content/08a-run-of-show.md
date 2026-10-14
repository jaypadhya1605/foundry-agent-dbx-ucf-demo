# 8. Run of show {#s8}

## The day (Mark's final agenda, Oct 13)
{widths: 1500 4560 3300}
| Time | Block | Jay |
|---|---|---|
| 8:30 | Intros + infrastructure review (Mark, Bryan, Yun, Chris G.) | Not there yet (lands ~10:15) |
| 9:15 | Scope, target resources, success criteria (Mark, Bryan) | |
| 10:00 | Hands-on design, setup, troubleshooting (breakouts) | Warm-ups from the car at ~10:45 (8.1) |
| 11:00–12:00 | Presentation and demo of Microsoft/Databricks connections (Jay, Joey) | Joey opens with the Databricks side (~10 min), then steps 1–13 (~45 min) |
| 12:00 | Lunch | |
| 1:00 | Reconnect + status (Mark, Bryan) | |
| 1:15–3:00 | Continued hands-on design, setup, validation | IMH sandbox (section 12) |
| 3:00–3:30 | Foundry end-to-end (Jay); Fabric (Joey) | Section 8.4 |
| 3:30 | Tasks, outputs, follow-ups (for example a demo for Brian, Andy and Shawn) | Write down follow-ups |

## 8.1 Pre-flight
**Sign in (Edge only):** Foundry and Databricks as `jay@brakekat.com`. Azure portal in the **BrakeKat** directory with the account that owns `rg-ai`. Option 2 needs no per-user browsers.

**Tabs, in this order** (links in Appendix A):
1. Image 1 (Yun's diagram) and image 3 (Option 2 slide)
2. Databricks table `imh_demo.clinical.patients`
3. Databricks → Settings → Identity and access → Groups → `imh_analyst`
4. Azure portal → `apim-imh-uc-66zpmtcbvhe7w` → APIs
5. Agent C (Foundry deep link)
6. Agent H (same link with `imh-uc-limited-agent`)
7. Databricks Query History, last hour
8. Log Analytics `law-imh-uc-66zpmtcbvhe7w` → Logs, with the KQL from Appendix D pasted
9. Azure portal → Container Apps job `job-imh-uc-agent`
10. Databricks Serving → `imh-foundry-gpt41-via-apim`, plus the SQL editor on `adb-demo-wh` with the two step 11 queries
11. Images 17–19 (Priority 2)
12. This document (fallback)

**Warm-ups (10 minutes before):**
- Agent C: "Show me patients at SLC." This wakes serverless compute (~20 s cold, ~7 s warm).
- SQL Warehouses → `adb-demo-wh` → **Start** (needed only for step 11).
- Start the job about 3 minutes before step 10 (its logs take 1–5 minutes to appear).
- Don't use agent H in the minute before the demo (3 tool calls a minute).
- In each agent, check the version picker shows C **v6** and H **v3** (refresh first).

**On the day:** you arrive at 11:00. Do the warm-ups from the car at ~10:45 (phone hotspot), or ask Joey to run agent C once and start `adb-demo-wh`. Joey opens with the Databricks side, so steps 3–4 may already be covered.

## 8.2 The steps (11:00–12:00 block, ~45 minutes)
Each step: **Open → Ask or Expect → Say → If it fails.** Read the blue boxes out loud.

### Step 1. Frame it on Yun's diagram (3 min) · Yun: all
**Open:** image 1 (Yun's diagram).
> SAY: Your two priorities are Microsoft agents using Databricks tools, and Databricks agents using Microsoft services. On Yun's diagram I'll walk the middle path: an agent calls APIM, APIM calls Databricks as a managed identity, and Unity Catalog decides what comes back. That's ③ and ④. Then ⑤: Databricks calling a Foundry model through the same APIM.

**Check yourself:** which component decides which rows come back? Unity Catalog.

### Step 2. The Option 2 slide (2 min)
**Open:** image 3.
> SAY: Option 2 is exactly what's running: Azure agent, APIM, MCP server, UC function, tables. The tools are Unity Catalog functions, so the agent can only run queries we wrote and fill in parameters. No free-form SQL. Your slide's examples were get_patient_demographics or get_claim_history; ours is get_patients by facility.

### Step 3. The rules live in Unity Catalog (4 min) · Yun: "Unity Catalog governs access"
**Open:** tab 2 (table `patients`) → Overview shows the row filter and column masks; then the schema → Functions.
**Expect:** row filter `fac_filter`; masks on `name` and `ssn`; functions `get_patients` and `get_patients_limited`.
> SAY: This is synthetic data: 12 patients in 4 facilities. Unity Catalog has three rules on this table: a row filter by facility, and masks on name and SSN. They're checked for whoever runs the query, every time. The agent's tool is this function, get_patients. It runs inside Databricks, so the rules always apply.

**If Joey already showed it:** say "As Joey showed, the rules sit on the table," then go to step 4.

### Step 4. Who Databricks thinks is calling (2 min) · Yun ④
**Open:** tab 3 (`imh_analyst` → Members).
**Expect:** `umi-imh-uc-agent`.
> SAY: APIM signs in to Databricks as this managed identity: an Entra identity with no password or secret. In Databricks it's a service principal in the analyst group, so every call through APIM gets analyst rules: all facilities, names redacted, SSNs masked. That's Yun's ④, machine-to-machine sign-in through Entra.

### Step 5. The gateway policy (3 min) · Yun ③ → ④
**Open:** tab 4 → "IMH UC functions MCP (via UMI)" → All operations → Inbound processing → `</>`.
**Expect:** `rate-limit-by-key`, two `set-header … delete`, `rewrite-uri`, `authentication-managed-identity`. Full text in Appendix C.1.
> SAY: This is the Microsoft-side gate. It rate-limits each caller, strips the caller's key so it never reaches Databricks, forwards to the Databricks MCP server for imh_demo.clinical, and gets an Entra token for Databricks as the managed identity. Nothing secret is stored in the policy.

### Step 6. Segment C live: Foundry agent → APIM → UC function (6 min) · Foundry box → ③ → ④ → UC
**Open:** tab 5 (agent C, v6).
**Ask:** "Show me patients at SLC."
**Expect:** tool call `imh_demo__clinical__get_patients` with `{"fac":"SLC"}`; 4 rows P001–P004, names `REDACTED`, SSN `***-**-1001` to `***-**-1004`; ~7 s warm, ~20 s cold.
**Ask:** "Show me all patients."
**Expect:** `get_patients` with `{}`; 12 rows across SLC, OGDEN, PROVO and STGEORGE, all masked.
> SAY: The agent chose the get_patients tool and filled in the facility. The call went to APIM, APIM called Databricks as the managed identity, and Unity Catalog applied the analyst rules, which is why names say REDACTED. Nobody signed in to Databricks, and the agent never held a Databricks credential.

**If it fails:** slow → cold serverless; wait 30 s and ask again. Approval prompt → wrong version selected (pick v6) or click Approve. 0 rows → check the tool-call arguments, run the script check (Appendix D) and show image 10 (section 7.7).
