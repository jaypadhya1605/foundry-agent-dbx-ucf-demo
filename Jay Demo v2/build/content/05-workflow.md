# 5. End-to-end workflow, hop by hop {#s5}

Each table follows one request from start to finish. The right column says where you can see that hop with your own eyes.

## 5.1 Segment C: Foundry agent → APIM → UC function (Priority 1)
{widths: 500 5160 3700}
| # | What happens | Where to see it |
|---|---|---|
| 1 | You ask agent C: "Show me patients at SLC." | Foundry playground |
| 2 | gpt-4.1 picks the only allowed tool, `imh_demo__clinical__get_patients`, with `{"fac":"SLC"}` | Foundry tool-call details |
| 3 | Foundry calls `https://apim-imh-uc-66zpmtcbvhe7w.azure-api.net/uc/mcp` with the APIM key from project connection `uc-fn-via-apim-umi` | Foundry → Tools |
| 4 | APIM checks the key, applies the rate limit and deletes the key header so it never reaches Databricks | APIM policy (Appendix C.1) |
| 5 | APIM gets an Entra token for Databricks as `umi-imh-uc-agent` and rewrites the path to `/api/2.0/mcp/functions/imh_demo/clinical` | APIM policy |
| 6 | The Databricks managed MCP server runs `get_patients(fac => "SLC")` on serverless compute as that service principal | Query History |
| 7 | Unity Catalog applies `fac_filter`, `mask_name` and `mask_ssn` for group `imh_analyst` | Table → Overview |
| 8 | 4 rows come back: names `REDACTED`, SSN `***-**-1001` to `***-**-1004` | Foundry answer; APIM log |

## 5.2 Segment H: the same path with guardrails
- Agent H calls `/uc-limited/mcp` with its own APIM key (subscription `imh-uc-limited-client`).
- **Inbound:** 3 tool calls a minute (only `tools/call` counts) and 200 requests a day per subscription.
- **Outbound:** if a tool result has more than 5 rows or is larger than 20,000 bytes, APIM replaces it with an MCP error and adds header `x-imh-gateway-block`.
- Unity Catalog still decides rows and columns. APIM only limits volume ("the blast radius").

## 5.3 Segment I: custom runtime with an Entra token (AKS stand-in)
{widths: 500 5160 3700}
| # | What happens | Where to see it |
|---|---|---|
| 1 | Container Apps job `job-imh-uc-agent` starts (manual trigger) | Job → Execution history |
| 2 | The Python client gets an Entra token as `umi-imh-uc-runtime`. No key in the container | Console logs: `auth=mi` |
| 3 | APIM `/uc-entra` validates the token: BrakeKat tenant, audience, and app ID on the allow-list. Anyone else gets 401 | APIM policy (Appendix C.3) |
| 4 | APIM calls Databricks as `umi-imh-uc-agent`, exactly as in C | Query History |
| 5 | `tools/list` returns 2 tools; `tools/call` returns 4 SLC rows, masked | Console logs (section 7.4) |

On AKS only the sign-in changes: workload identity instead of the Container Apps managed identity. Same code, same APIM API.

## 5.4 Segment J: Databricks → APIM → Foundry model (Priority 2, Yun ⑤)
{widths: 500 5160 3700}
| # | What happens | Where to see it |
|---|---|---|
| 1 | The SQL editor on `adb-demo-wh` runs `ai_query('imh-foundry-gpt41-via-apim', …)` | SQL editor |
| 2 | Serving endpoint `imh-foundry-gpt41-via-apim` (external model with AI Gateway: usage tracking, 60 calls a minute) reads the APIM key from secret scope `imh-apim` | Serving → endpoint |
| 3 | APIM `/aoai` checks the key (subscription `databricks-ai-gateway`) and applies `llm-token-limit`: 20,000 tokens a minute | APIM policy (Appendix C.4) |
| 4 | APIM signs in to Foundry with its managed identity and forwards to gpt-4.1 on `aif-wu3` | APIM log |
| 5 | The answer comes back as a column in the SQL result | SQL editor |

## 5.5 Genie One → Microsoft 365 (Priority 2, screenshots)
- Genie One, Databricks' own agent, answered "patients per facility" from Unity Catalog as jay.
- Through Databricks' built-in Microsoft 365 connector (Jay signed in on Oct 13), it drafted an Outlook email with the summary (images 17–19).
- No app registration and no code. Work IQ is the next step: it needs Copilot licensing, and cyber has to clear PHI leaving the Azure boundary.
