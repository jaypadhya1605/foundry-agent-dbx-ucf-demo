# 2. Concepts in plain English {#s2}

Learn these first, one minute each. The right column says where you'll point at it in the room.

{widths: 1900 4860 2600}
| Term | Plain English | Where you'll see it |
|---|---|---|
| **MCP** | A standard way for an agent to list tools (`tools/list`) and call them (`tools/call`) over HTTPS. Like USB-C for agent tools | Foundry agent's tool; APIM logs |
| **UC function** | A SQL function saved in Unity Catalog. `get_patients(fac)` is a pre-written query; the agent fills in `fac` but can't change the SQL | Catalog → `imh_demo.clinical` → Functions |
| **Databricks managed MCP server** | Databricks hosts the MCP endpoint. Every table function in a schema becomes a tool: `/api/2.0/mcp/functions/imh_demo/clinical` | APIM backend URL |
| **Row filter / column mask** | Unity Catalog rules checked for whoever runs the query: the filter decides rows (facility), masks decide what `name` and `ssn` show | Table `patients` → Overview |
| **APIM** | Azure API Management, the Microsoft-side gateway: checks the caller (key or Entra token), applies policies (rate, quota, row cap), signs in to Databricks, logs every call | Azure portal → APIM → APIs |
| **Managed identity (UMI)** | An Entra identity for an Azure resource. No password or secret; Azure issues its tokens | `umi-imh-uc-agent` (APIM → Databricks) and `umi-imh-uc-runtime` (job → APIM) |
| **Service principal + OAuth M2M** | The managed identity is registered in Databricks as a non-human user in group `imh_analyst`. APIM signs in **as itself**, not as the caregiver (Yun ④) | Databricks → Groups → `imh_analyst` |
| **Tool allow-list** | The agent may call only `imh_demo__clinical__get_patients` | Agent definition |
| **External Data Access (EDA)** | A metastore switch that lets outside engines read Unity Catalog storage directly. Not needed here | Metastore settings (screenshot) |
| **Serverless compute** | Databricks-managed compute that runs the MCP function calls. First call is ~20 s cold | Query History: "Serverless compute" |
| **Unity Gateway** | Databricks' new (Oct 2026) gateway for MCP and models: grants, policies and tracing per MCP. Our APIM path uses the legacy MCP URL, which bypasses it | AI/ML → AI Gateway |

## Four layers, one sentence each
The answer to "what stops an agent from pulling everything?":
1. **Agent allow-list** picks the tool.
2. **UC function** fixes the query (no free-form SQL).
3. **APIM** limits who, how often and how much (5 rows / 20 KB on `/uc-limited`, 3 tool calls a minute, 200 a day).
4. **Unity Catalog** decides rows and columns for the identity that runs it.

## Identity: who is who on each hop
- **Agent → APIM:** Foundry agents present an APIM subscription key stored in the Foundry project connection. The custom runtime presents an Entra token from its own managed identity (no key).
- **APIM → Databricks:** APIM signs in as `umi-imh-uc-agent`, a service principal in `imh_analyst`. Every call through APIM gets analyst rules: all facilities, names `REDACTED`, SSNs masked.
- **What Databricks does not see:** the caregiver. That's Yun's design for ④ (machine to machine). Per-user sign-in (OAuth passthrough) also works and was proven separately (segments A, B and K); single sign-on needs Foundry and Databricks in the same Entra tenant.
- **No secret between APIM and Databricks:** Entra issues the managed identity's tokens; nothing is stored in the policy.

## External Data Access, in one minute
- EDA is a metastore switch that lets engines outside Databricks read Unity Catalog storage directly (for example Fabric mirroring).
- Option 2 doesn't need it: the UC function runs inside Databricks on serverless compute, and only the result leaves.
- Proven Oct 12: EDA turned off on the BrakeKat metastore, the agent still returned the same rows (images 13 and 14), then EDA was restored for Joey.
- Fabric mirroring does need EDA, plus grants in Fabric: a second governance layer, which is what Mark wants to avoid.

## Legacy MCP URL vs Unity Gateway
- Today APIM calls Databricks' legacy managed MCP URL `/api/2.0/mcp/functions/imh_demo/clinical`. It proves the pattern but bypasses Unity Gateway.
- Unity Gateway (Databricks, Oct 2026) puts MCP services and models behind grants, policies and tracing: `/ai-gateway/mcp-services/…`. For a new build, point APIM at that URL so both gateways apply. Not tested through APIM yet.
- The Genie One beta MCP endpoint sunsets Oct 31, 2026. Option 2 doesn't use it.
