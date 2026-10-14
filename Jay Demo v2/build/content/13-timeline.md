# 13. How we got here: Oct 11–15 {#s13}

All times Eastern.

{widths: 2000 7360}
| When | What happened |
|---|---|
| Oct 11, 10:21 PM | Foundry project `proj-imh-uc-demo` created in the BrakeKat tenant. Overnight setup: users `jay@`, `clinician-slc@`, `analyst@`; the three groups; the synthetic table with its row filter and masks; Genie space; sign-in apps |
| Oct 12, 12:10 AM | Segment A passed (per-user Genie from Foundry) |
| Oct 12 | Segment B passed (per-user UC functions, tested as all three users) |
| Oct 12, 3:03–3:32 PM | Azure side created: `umi-imh-uc-agent` and Log Analytics (3:03), then APIM (3:32) |
| Oct 12, 4:32–4:37 PM | APIM's managed identity added to the workspace and to `imh_analyst` (images 8 and 9) |
| Oct 12, 4:41–4:59 PM | Segment C passed (script 4:41, agent 4:53–4:57); segment D Query History at 4:59 (images 10 and 11). APIM log query at 6:56 PM (image 12) |
| Oct 12, ~8:17 PM | Segment E: External Data Access turned off, the agent still worked, then it was restored (images 13 and 14) |
| Oct 12, ~10:40–10:50 PM | Runtime deployed: `umi-imh-uc-runtime`, the Container Apps environment and `job-imh-uc-agent` |
| Oct 12, ~11:14–11:21 PM | Bicep deployments `imh-apim-umi` and `imh-uc-runtime` ran in BrakeKat |
| Oct 13, 10:44 AM | Unity Gateway MCP list captured (image 16) |
| Oct 13, 11:31–11:52 AM | Genie One answered patients per facility, then drafted the Outlook email (images 17–19) |
| Oct 13 | Segments G (Genie through APIM), H (gateway limits) and I (runtime with Entra token) passed |
| Oct 13, 2:32 PM | Segment J: `Setup-DatabricksSide.ps1` ran (image 15); IaC package `infra\uc-agent-gateway\` completed |
| Oct 14, morning | Learning session mapped to Yun's diagram. IMH thread: MCP on `apim-ih-ent-eap-dev` is in cyber review |
| Oct 14, 1:13 PM | Segment K passed as jay (Genie One MCP through Unity Gateway, per user) |
| Oct 14, ~2:00 PM | Scope narrowed to Option 2. Foundry cleanup (image 7); C v6 and H v2 fix |
| Oct 14, ~3:40 PM | H v3: same as v2, but the tool's connection is referenced by name so the Foundry UI shows it. Re-tested: SLC returns 4 rows; all facilities is blocked |
| Oct 14, 2:05–2:45 PM | Re-verification of C, H, D, I and J (section 7.1); IaC parity (`--allowed-tools`); this playbook and document |
| Oct 15 | Onsite: 11:00–12:00 demo, 1:15–3:00 sandbox, 3:00–3:30 Foundry end-to-end |
