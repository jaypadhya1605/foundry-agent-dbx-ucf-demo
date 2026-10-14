# 7. Proof: what we saw {#s7}

## 7.1 Re-verification, Oct 14, 2:05–2:45 PM ET
{widths: 1300 2900 3960 1200}
| Segment | Test | Result | Pass |
|---|---|---|---|
| Script | `/uc/mcp`: `tools/list`, then SLC | Only `get_patients` and `get_patients_limited` are tools (filter and mask functions aren't); 4 SLC rows, masked, ~22 s cold | Yes |
| C | Agent C v6: "Show me patients at SLC." then "Show me all patients." | `get_patients {"fac":"SLC"}` 4 rows (~7 s); `get_patients {}` 12 rows across 4 facilities; all masked | Yes |
| H | Agent H v2 (v3 re-tested about 3:40 PM): "Show me all patients across every facility." | Blocked: 12 rows is over the 5-row limit. Then "SLC" returns 4 rows | Yes |
| D | Query History + APIM logs | SQL ran as `umi-imh-uc-agent` on serverless compute; APIM logged every call, blocked ones as 200 | Yes |
| I | Job `job-imh-uc-agent`, then Jay's own token | Job: Entra token accepted on `/uc-entra`, 4 SLC rows, masked, 39 s. Jay's Azure CLI token: 401 | Yes |
| J | `ai_query` and `get_patients_limited(NULL, 50)` as jay | Model answered through APIM; 10 rows (Unity Catalog's cap) | Yes |

## 7.2 What the analyst identity sees (agents C and H, job I)
{widths: 1300 1700 1900 1400 3060}
| patient_id | name | ssn | facility | diagnosis |
|---|---|---|---|---|
| P001 | REDACTED | `***-**-1001` | SLC | Type 2 diabetes |
| P002 | REDACTED | `***-**-1002` | SLC | Hypertension |
| P003 | REDACTED | `***-**-1003` | SLC | Congestive heart failure |
| P004 | REDACTED | `***-**-1004` | SLC | COPD |

"Show me all patients" adds the other facilities, masked the same way:

{widths: 1500 1500 1700 4660}
| Facility | Patients | SSN ends | Diagnoses |
|---|---|---|---|
| OGDEN | P005–P007 | 2005–2007 | Asthma; CKD stage 3; Atrial fibrillation |
| PROVO | P008–P010 | 3008–3010 | Community-acquired pneumonia; Major depressive disorder; Osteoarthritis of knee |
| STGEORGE | P011–P012 | 4011–4012 | Migraine; Hyperlipidemia |

> NOTE: All values are synthetic. The live table was seeded during setup with its own synthetic rows, so the seed rows in the IaC (Appendix B) differ from these. The rules are the same.

## 7.3 Agent H: the gateway block
```
Blocked by gateway policy: the result has 12 rows (limit 5) or is larger than 20000 bytes.
Ask a narrower question, for example one facility.
```
- Response header: `x-imh-gateway-block: row-limit 12>5`.
- Foundry's REST API reports it as HTTP 400 `tool_user_error`. APIM logs the call as 200, because the block is an MCP error inside a normal response.
- "OK, just SLC then." returns the 4 SLC rows. A 4th tool call inside one minute gets 429 "Rate limit is exceeded".
- Why the fix mattered: before Oct 14, H v1 sent `fac: ""` for "all facilities". That returns 0 rows, so the cap never fired. H v2 leaves `fac` out. H v3 keeps that and references its connection by name, so the Foundry UI shows the tool.

## 7.4 Segment I: the job's console log (Oct 14, 18:11:08 UTC, 39 s)
Execution `job-imh-uc-agent-597gxc7-hhjsk`. Key lines, with the JSON wrapped for reading:

```
# url=…/uc-entra/mcp auth=mi
initialize: HTTP 200                  correlation c129cc9d-5b19-488e-81b1-e47bd124a587
notifications/initialized: HTTP 200   correlation 37ce31d0-2910-4f6c-bd71-b45a425bb2db
tools/list: HTTP 200                  correlation 3d1570e8-cbd8-45f3-a0e3-18963e108173
tools: ['imh_demo__clinical__get_patients', 'imh_demo__clinical__get_patients_limited']
tools/call: HTTP 200                  correlation 366baa32-4d63-43fd-b323-44d03911d6ea
{"columns": ["patient_id", "name", "ssn", "facility", "diagnosis"],
 "rows": [["P001", "REDACTED", "***-**-1001", "SLC", "Type 2 diabetes"],
          ["P002", "REDACTED", "***-**-1002", "SLC", "Hypertension"],
          ["P003", "REDACTED", "***-**-1003", "SLC", "Congestive heart failure"],
          ["P004", "REDACTED", "***-**-1004", "SLC", "COPD"]]}
```

The 401 check: Jay's own Azure CLI token on the same URL is refused with HTTP 401 "A valid Entra token for the UC agent gateway is required.", because his app isn't on the allow-list. Command in Appendix D.

## 7.5 Segment J: SQL run on `adb-demo-wh` as jay
```sql
SELECT ai_query('imh-foundry-gpt41-via-apim',
                'In one sentence, what does Unity Catalog govern?') AS answer;   -- one-sentence answer

SELECT count(*) AS rows_returned
FROM imh_demo.clinical.get_patients_limited(NULL, 50);                          -- 10

SELECT current_user();                                                           -- jay@brakekat.com
```
- The second query asked for 50 rows and got 10: Unity Catalog's own cap, on top of APIM's.
- Image 15 shows the setup script's checks: default 5 rows, capped 10 rows, endpoint READY, DATABRICKS-SIDE-COMPLETE.

## 7.6 Segment D: where each call is recorded
{widths: 2400 6960}
| Record | What it shows |
|---|---|
| Databricks Query History | ``SELECT * FROM `imh_demo`.`clinical`.`get_patients`(fac => "SLC")``<br>User `umi-imh-uc-agent`; Source "Spark Connect API"; Compute "Serverless compute for Notebooks" |
| APIM gateway logs | APIs `imh-uc-functions-mcp` and `imh-uc-functions-mcp-limited`: POST 200 (MCP call), POST 202 (MCP notification), GET 405 (stream request declined, harmless), with subscription and CorrelationId |
| Foundry | The tool call's name and arguments in the run details |
| Job console logs | Each MCP step with its HTTP status and correlation ID (7.4) |

## 7.7 Screenshots from the build
@img 10-segment-c-foundry-agent-slc-masked.png | Image 10. Segment C: agent C answers for SLC with names and SSNs masked
@img 11-segment-d-query-history-umi.png | Image 11. Segment D: Query History shows the SQL ran as `umi-imh-uc-agent`
@img 12-segment-d-apim-gateway-logs.png | Image 12. Segment D: APIM gateway logs in Log Analytics
@img 13-segment-e-eda-disabled.png | Image 13. Segment E: External Data Access turned off on the metastore (Oct 12)
@img 14-segment-e-agent-works-with-eda-off.png | Image 14. Segment E: the agent still works with External Data Access off
@img 15-segment-j-databricks-side-complete.png | Image 15. Segment J: Databricks side complete (row cap, endpoint READY)
@img 16-unity-gateway-mcp-list.png | Image 16. Unity Gateway in the BrakeKat workspace: the MCP services list (Oct 13)
@img 17-genie-one-patients-per-facility.png | Image 17. Priority 2: Genie One answers "patients per facility" from Unity Catalog
@img 18-priority2-genie-one-drafts-email.png | Image 18. Priority 2: Genie One drafts an email through the Microsoft 365 connector
@img 19-priority2-outlook-draft.png | Image 19. Priority 2: the draft in Outlook

## 7.8 Evidence from the dry run
@evidence
