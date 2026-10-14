# 9. If something breaks {#s9}

{widths: 2600 4160 2600}
| Symptom | Fix | Fallback |
|---|---|---|
| First agent answer takes 20+ s | Serverless cold start. Talk through step 5 while it runs | — |
| Approval prompt in C or H | An old version is selected: pick C v6 or H v3, or click Approve | — |
| H's Tools panel is empty | H v2 is selected (it references its connection by full ID, so the UI hides the tool); pick H v3 | Chat still works on v2; show the YAML tab |
| C returns 0 rows | Check the tool-call arguments: they should be `{"fac":"SLC"}` or `{}` | Image 10 + script check (Appendix D) |
| H returns rows for "all" | The agent sent a facility. Ask "All facilities, no filter." | Script check with `--args '{}'` |
| 429 on H | Rate limit (3 tool calls a minute). Wait 60 s and say "that's the limit working" | — |
| Query History empty | Widen the time range; clear the Compute filter (MCP calls run on serverless, not `adb-demo-wh`) | Image 11 |
| APIM logs empty | Ingestion lag 2–5 minutes; widen to `ago(24h)` | Image 12 |
| Job logs empty | Lag 1–5 minutes; show the previous run | Section 7.4, or run the job commands in Appendix D |
| `ai_query` error | Start `adb-demo-wh`; check the endpoint is READY | Image 15 |
| Foundry opens the wrong tenant | Use the deep link with `?tid=8d038e6a-9b7d-4cb8-bbcf-e84dff156478` (Appendix A) | — |
| Everything is down | Walk section 8 from this document | Screenshots in section 7.7 |

> NOTE: If a live step fails twice, show its screenshot and move on. The screenshots prove the same thing, and the room cares about the pattern, not the click.

## Words for a failure in the room
> SAY: That's serverless waking up, which is a real thing you'll see in production too. While it runs, here's what it's doing.

> SAY: Let me show you a recorded run instead; it's the same call and the same rules.
