### Step 7. Segment H: gateway guardrails (5 min) · Open item: result-size and row limits
**Open:** tab 6 (agent H, v3).
**Ask:** "Show me all patients across every facility."
**Expect:** blocked. The gateway's text: "Blocked by gateway policy: the result has 12 rows (limit 5) or is larger than 20000 bytes. Ask a narrower question, for example one facility." Foundry shows it as a tool error, or the agent rewords it and suggests one facility. **Both are a pass.**
**Ask:** "OK, just SLC then." → 4 rows.
> SAY: Same identity, same data, different APIM route. This one has guardrails: more than 5 rows or 20 KB comes back as an error, 3 tool calls a minute, 200 a day. APIM doesn't know your PHI rules and shouldn't; Unity Catalog still decides the rows. APIM limits the blast radius. That's your open item on result-size limits.

**Add (the layers):**
> SAY: In testing, an agent picked the wrong function, so the agent now has an allow-list too. The allow-list picks the tool, the function fixes the query, APIM limits volume, and Unity Catalog decides rows and columns.

**Optional 429:** ask 4 SLC questions inside a minute; the 4th gets "Rate limit is exceeded".
> SAY: That's the rate limit doing its job.

**If it isn't blocked:** the agent sent a facility. Ask again: "All facilities, no filter." Or run the script check (Appendix D).

### Step 8. Segment D: the audit trail (5 min)
**Open:** tab 7 (Query History, last hour). Filter **User** = `umi-imh-uc-agent` if the list is busy.
**Expect:** ``SELECT * FROM `imh_demo`.`clinical`.`get_patients`(fac => "SLC")``, User `umi-imh-uc-agent`, Source "Spark Connect API", Compute "Serverless compute for Notebooks" (not `adb-demo-wh`).
**Open:** tab 8 (Log Analytics) → run the KQL (Appendix D).
**Expect:** rows for `imh-uc-functions-mcp` and `imh-uc-functions-mcp-limited`: POST 200, POST 202, GET 405, with ApimSubscriptionId and CorrelationId.
> SAY: Both sides keep a record. Databricks shows the exact SQL the tool ran and that it ran as the agent identity. APIM shows which subscription called, the response and a correlation ID. A blocked result still logs 200 in APIM, because the block comes back as an MCP error inside a normal response.

**Concept:** POST 202 = MCP notification. GET 405 = the client asks for a stream and Databricks declines (harmless).
**If empty:** APIM logs lag 2–5 minutes, so widen to `ago(24h)`. Show images 11 and 12 (section 7.7).

### Step 9. Segment E: no External Data Access (1 min) · Screenshots only
**Open:** images 13 and 14 (section 7.7).
> SAY: External Data Access lets outside engines read Unity Catalog storage directly. We turned it off on October 12 and the agent still worked, because the function runs inside Databricks. Fabric mirroring is the path that needs it, and that's out of scope.

> NOTE: Never toggle External Data Access live. It's Joey's metastore.

### Step 10. Segment I: custom runtime, Entra token, no key (4 min) · Yun ③ + AKS box
**Open:** tab 9 → **Run now** (about 3 minutes earlier) → Execution history → latest → Console logs.
**Expect:** `# url=…/uc-entra/mcp auth=mi`, `initialize: HTTP 200`, the two tool names, `tools/call: HTTP 200`, then 4 SLC rows, masked (section 7.4). The Oct 14 run took 39 s; logs appeared within about 2 minutes.
**Optional:** run the 401 check (Appendix D) and show the output.
> SAY: This stands in for your AKS pod: a Python client with its own managed identity and no key in the container. APIM validates its Entra token: right tenant, right audience, and its app ID is on the allow-list. My own token gets a 401 because I'm not on the list. On AKS it's the same code with workload identity.

**If the logs are empty:** they lag 1–5 minutes; show the previous run or section 7.4.

### Step 11. Segment J: Databricks → APIM → Foundry model (4 min) · Yun ⑤ (⑥ is public here) · Priority 2
**Open:** tab 10: Serving → `imh-foundry-gpt41-via-apim` (AI Gateway: usage tracking, 60 calls a minute), then the SQL editor on `adb-demo-wh`.
**Run, one at a time:**
```sql
SELECT ai_query('imh-foundry-gpt41-via-apim',
                'In one sentence, what does Unity Catalog govern?') AS answer;

SELECT count(*) AS rows_returned
FROM imh_demo.clinical.get_patients_limited(NULL, 50);
```
**Expect:** a one-sentence answer (~18 s if the warehouse is starting), then **10**.
> NOTE: Use `count(*)` in the room. As jay (`imh_phi_full`), the rows themselves show full synthetic names and SSN-like values.

> SAY: Now the other direction, Yun's ⑤: Databricks calling a Foundry model. The serving endpoint points at our APIM, not straight at Foundry. APIM applies a token limit and signs in to Foundry with a managed identity, and Databricks' AI Gateway adds its own usage tracking and rate limit. And Unity Catalog can cap rows itself: I asked this function for 50 and got 10.

**If it fails:** start `adb-demo-wh` and check the endpoint is READY; otherwise show image 15.

### Step 12. Priority 2: a Databricks agent writes to Microsoft 365 (3 min) · Screenshots
**Open:** images 17, 18 and 19 (section 7.7).
> SAY: Your second priority is Databricks agents working with Microsoft services. Databricks' own agent, Genie One, answered from Unity Catalog and then drafted this Outlook email through Databricks' built-in Microsoft 365 connector, signed in as me. No app registration, no code. Work IQ is next: it needs Copilot licensing, and cyber has to clear PHI leaving the Azure boundary. The reverse direction, Copilot Studio or Teams calling Databricks, is ① on Yun's diagram and isn't built.

### Step 13. Limitations and this afternoon (3 min)
> SAY: Three things to be clear about. One: this is our demo tenant with synthetic data on public endpoints. The private network isn't built: Private Link from APIM to Databricks, and NCC for serverless back to APIM. Two: on this path Databricks sees the agent's identity, not the caregiver's. That's Yun's design for ④; per-user sign-in works too, and we proved it separately. Three: we call Databricks' legacy MCP endpoint. For a new build, point APIM at the Unity Gateway URL so both gateways apply. This afternoon in your sandbox we can stand up the same pattern: one UC function, APIM's identity as a service principal, and one APIM API.

## 8.3 After step 13: the questions most likely to come
Answers are in section 10. Be ready for these four first:
- Do we need External Data Access? (No.)
- Who decides what the agent sees? (Unity Catalog, always.)
- Does Databricks know which caregiver asked? (Not on this path; it sees the agent identity.)
- What's the kill switch? (Disable the APIM subscription or remove the app from the allowed list.)

## 8.4 3:00–3:30: Foundry end-to-end (~20 minutes)

### 1. Foundry project tour (5 min)
**Open:** agents C and H → Tools: the MCP tool → its connection (APIM key); model gpt-4.1; the allow-list.
> SAY: The agent is a prompt, a model and one tool. The tool is just an MCP URL on APIM and a key in a project connection, which you can swap for an Entra token.

### 2. Policies side by side (8 min)
**Open:** in APIM, the inbound policy of `/uc` (key + managed identity), then `/uc-limited` (rate, quota, row and size cap: show the outbound `rowCount > 5` block), then `/uc-entra` (`validate-azure-ad-token` with `client-application-ids`). Full text in Appendix C.
> SAY: Three routes, one Databricks backend. The first checks a key and signs in to Databricks as the managed identity. The second adds rate, quota and a row and size cap on the way out. The third takes no key at all: only an Entra token from an app on its list. Your control plane picks the route for each agent.

### 3. One call traced (5 min)
**Open:** a Foundry chat → APIM log (CorrelationId) → Databricks Query History (identity and SQL).
> SAY: One question, three records that tell the same story: Foundry shows the tool call, APIM shows the caller and a correlation ID, and Databricks shows the exact SQL and the identity that ran it.

### 4. Infrastructure as code (7 min)
**Open:** `infra\uc-agent-gateway\`.
- Bicep: deployed and tested in BrakeKat.
- Terraform (Azure + Databricks): written; `terraform validate` not run yet.
- `databricks\Setup-DatabricksSide.ps1`: ran Oct 13.
- `foundry\create_agents.py`: new `--allowed-tools`.
- `clients\python_mcp_client.py`: smoke tests.
> SAY: Everything you saw is in this folder. IMH changes the parameters: tenant, workspace, catalog and schema, groups, and the gateway's app ID.

### 5. Sandbox results (5 min)
Show whatever the 1:15–3:00 hands-on produced (section 12).
