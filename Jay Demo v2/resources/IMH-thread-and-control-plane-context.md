# IMH thread + Azure Agents Control Plane context (CRITICAL)

Captured 2026-10-12 from Jay. Source of truth for what IMH (Mark Nielsen) asked and what the
team has said. Onsite: Thursday 2026-10-15.

## People

- **Mark Nielsen** (IMH) — driving the ask; wants Foundry/Copilot to use Databricks UC governance
  with no second access layer.
- **Chris Tava** (Microsoft) — working with IMH CloudOps and Brian's team; proposed the
  APIM/MCP → UC function approach.
- **Brian's team** (IMH) — stood up the Azure Agents Control Plane (APIM + AKS).
- **Joey Brakefield** (Microsoft Data SE) — Databricks/Fabric sharing options; owns BrakeKat tenant.
- **Lee Reese** — added Joey and Chris to the Teams chat.

## Mark's questions (Teams, 2026-10-08 → 10-10)

1. "Before Thursday, what do we need to prep to set up the configuration? Are we required to
   configure Azure Databricks to allow **External data access**? If so, what else do we need so
   our data remains secure?" (IMH metastore screenshot: External OpenSharing Enabled, recipient
   token 365 days, org `intermountain_health_tenant`, **External data access = Disabled**.)
2. Goal: "Foundry, Copilot, etc. can access our enterprise data platform (Azure Databricks Unity
   Catalog) **without creating a new access/governance layer** — use UC governance and access
   controls."
3. "Our agents in Azure are deployed via **AKS/ACA** — is that right? Should Thursday be about
   connecting those with Unity Catalog? What must be true to make that connection? Is External
   Data Access required for this architecture?"
4. EDA decision needs sign-off from **Select Health, Scripius, other business leaders, cyber, and
   the DB admin team**. **They reviewed it multiple times in the past year and declined each time.**
5. Proposed agenda: **morning** = cross-team strategic conversation; **afternoon** = DB/MSFT
   connection configurations:
   - Connecting **MSFT tools → Databricks agents**
   - Connecting **Databricks tools → MSFT agents**
6. IMH invitees asked about this pattern; if EDA is a no-go, pivot to other **Unity
   Gateway/APIM/Foundry** integrations — Mark has "a long list" worth POCs.

## Team answers so far

- **Chris / Mark Nielsen thread:** Brian's team stood up the **Azure Agents Control Plane**:
  APIM (supports MCP) + AKS. Resources backed by **User-Assigned Managed Identities**, can be
  locked down in **Agents 365** with an **AI kill switch** (Disable on the agent identity).
  Repo: <https://github.com/microsoft/azure-agents-control-plane>
- **Pattern:** **Azure Agent → API Management → MCP Server → Unity Catalog Function →
  Databricks Tables.**
- **EDA answer (sent):** APIM/MCP → UC function **does not need External Data Access** when the
  function executes inside Databricks. It still needs an authorized identity, UC function/data
  permissions, and network access.
- **Fabric UC mirroring DOES need EDA** on the metastore, plus `EXTERNAL USE SCHEMA` and read
  grants for the connection identity. UC policies don't carry into Fabric — access must be
  configured in Fabric too (a second governance layer — conflicts with Mark's goal).
  Prereqs: <https://learn.microsoft.com/en-us/fabric/mirroring/azure-databricks-tutorial#prerequisites>
- Keep the two as **separate setup paths** for Thursday; confirm which one before touching the
  metastore setting.
- **Joey's alternatives (Friday):** Fabric native sharing (lakehouses, warehouses, Epic Cogito
  direct sharing Cogito Cloud → IMH tenant, Power BI reports); Databricks native sharing (Clean
  Rooms, Delta Sharing/OpenSharing — unsure whether Metric Views / AI/BI dashboards can be shared,
  Joey checking before the 15th); file sharing as fallback.

## Images Jay shared (2026-10-12) — what they show

1. Databricks app `foundry-genie-imh-uc` redirect URLs (Genie + `uc-fn-imh-mcp-v3`) and scopes.
2. Foundry agent `imh-uc-fnct-1-agent` v10 calling `imh_demo__clinical__get_patients({"fac":"SLC"})`
   via `uc-fn-imh-mcp-v3` as jay → 4 SLC rows, full values (success).
3. Teams: Mark's EDA question + metastore settings screenshot (EDA Disabled).
4. Teams: Mark asks whether Thursday is about connecting AKS/ACA agents with UC, and whether EDA
   is required.
5. Diagram: Caller → APIM → AKS → Foundry / CosmosDB / SQLDB; **UMI** dotted to APIM, AKS and
   each resource; **Agent 365 Identity** under UMI.
6. "Azure Agents Control Plane": callers (M365 Copilot, other MCP APIs, MCP Inspector, VS Code)
   → APIM (Policies, Metrics, Logs) → AKS (Agent pods, Entra Agent Identity, RBAC roles, Agents
   365 registry with **AI Kill Switch**, Agent Learning in-process RL); Azure Monitor; Resources:
   AI Foundry, Foundry IQ, Cosmos DB, Storage, Key Vault, ACR, Private Network, RBAC, Purview,
   Fabric IQ, Fabric Data Agents. **Databricks is not in the diagram.**
7. Entra "Next Best Action Agent" agent identity page: Status Active, **Disable** button
   (kill switch), sponsors/owners, agent blueprint, CA policies, access packages.
8. Teams: Mark's EDA sign-off note + morning/afternoon agenda; Joey's sharing alternatives.

Original images were pasted into chat; save copies next to this file for decks.

## Coverage map — demo vs. what IMH asked

| IMH ask | Status |
|---|---|
| UC governs agent access, no second layer | **Proven** (BrakeKat Proof B: Genie + UC function, per-user rows/masks, Query History shows real user) |
| EDA not required for agent → UC function | **Proven** 2026-10-12: EDA toggled off on the BrakeKat metastore, UC function + APIM paths still worked |
| APIM in the path (policies, logs, rate limit) | **Proven** — `/uc`, `/genie`, `/uc-limited` (rate, quota, >5 rows / >20 KB blocked), `/aoai`; GatewayLogs in LAW |
| AKS/ACA agents with **UMI** (agent identity, not user) → UC | **Proven on ACA** — job as `umi-imh-uc-runtime` → APIM `/uc-entra` (Entra token, allow-list) → APIM UMI (Databricks SP in `imh_analyst`) → UC. AKS = same client with `--auth workload` (not registered in BrakeKat) |
| Agents 365 kill switch | **Talk track only** — Brian's team owns; disabling the agent identity stops new tokens |
| Databricks tools → MSFT agents | **Covered** (Genie MCP, UC functions MCP, both direct and via APIM) |
| MSFT tools → Databricks agents | **Partial** — APIM `/aoai` (Foundry model behind APIM) live; Databricks external-model endpoint scripted (`Setup-DatabricksSide.ps1`), needs jay@brakekat.com to run |
| Private networking (Yun's diagram) | **Not built** in BrakeKat (would break the public demo); talk track: StandardV2 APIM VNet integration + Private Link |
| Fabric mirroring | **Out of scope** — needs EDA, IMH has declined; offer Joey's alternatives |
