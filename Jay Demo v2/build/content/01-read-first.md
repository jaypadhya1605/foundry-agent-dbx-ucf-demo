# 1. Read this first {#s1}

## The ask
IMH's Scope and Priorities, from Yun's slide:
1. **Connect Microsoft agents to Databricks tools** (Genie One MCP, Genie agents, UC functions and so on).
2. **Connect Databricks agents with Work IQ, Microsoft Graph and other Microsoft MCP services, in both directions.**

## The one-line answer for Mark
An Azure agent can query Databricks **through Unity Catalog, with Unity Catalog as the only governance layer**, using **Azure agent → APIM → MCP server → UC function → Databricks tables**. It does **not** need External Data Access, because the function runs inside Databricks.

## The story in one breath (memorize this)
> SAY: Your agents, Foundry today and AKS tomorrow, call Databricks through APIM. APIM is the Microsoft-side gate: who may call, how often, how much comes back, and a log of every call. Behind it, Databricks exposes Unity Catalog functions as MCP tools, and Unity Catalog alone decides which rows and columns come back. No External Data Access, no copy of the data, and no secret between APIM and Databricks.

**Two gateways, one decider:** APIM (Microsoft side) and Unity Gateway (Databricks side, for new builds) control access. **Unity Catalog decides the data.**

## What we show for each priority
{widths: 1000 4760 2200 1400}
| Priority | What we show | Proof | Steps |
|---|---|---|---|
| 1 | Foundry agent → APIM → Databricks MCP → UC function, with gateway guardrails | C, H, D live; E screenshots | 3–9 |
| 1 | Custom runtime (AKS stand-in) → APIM with an Entra token, no key | I live | 10 |
| 2 | Databricks → APIM → Foundry model (`ai_query`) | J live | 11 |
| 2 | Databricks agent (Genie One) → Microsoft 365 → Outlook draft | Screenshots (Oct 13) | 12 |

## IMH context (frame it this way)
- **Mark Nielsen's goal:** Foundry, Copilot and other agents use IMH's Databricks data **without a new access or governance layer**. Unity Catalog stays the only one (no second layer in Fabric).
- **External Data Access:** IMH reviewed it several times in the past year and declined each time; it needs sign-off from Select Health, Scripius, business leaders, cyber and the DB admin team. Mark said: if EDA is a no-go, pivot to Unity Gateway / APIM / Foundry integrations. That is Option 2.
- **What we already told them about EDA:** APIM/MCP → UC function does **not** need External Data Access when the function runs inside Databricks. It still needs an authorized identity, UC permissions and network access. Fabric mirroring **does** need EDA, and its access rules live in Fabric too.
- **Which project?** Not one project. **Ventures** is the clearest case for Microsoft agents needing Databricks MCP tools; a handful of others benefit from Microsoft MCP tools offered to Databricks agents.
- **What IMH already has:** Brian's team runs an Azure Agents Control Plane: APIM (supports MCP) + AKS, user-assigned managed identities, and an Agents 365 kill switch. Option 2 plugs into it.
- **Tony Sargent's call** (per Chris): getting Databricks data into Azure agents through APIM / MCP calls to Databricks APIs. Same pattern.
- **IMH's own APIM** `apim-ih-ent-eap-dev` already calls the Databricks REST API; Databricks MCP through it is in cyber review (Yun, Oct 14). Thursday's hands-on uses the Databricks sandbox.

## Who's who
{widths: 2400 6960}
| Person | Role |
|---|---|
| Mark Nielsen (IMH) | Drives the ask; runs the day with Bryan |
| Bryan (IMH) | Runs the day with Mark |
| Yun Layton (IMH) | Drew the target architecture (section 3); checks APIM/MCP status with Bhaskara |
| Bhaskara Yandava (IMH) | Builds IMH's APIM ↔ MCP setup |
| Peter Jones (IMH) | Databricks sandbox admin |
| Brian, Andy, Shawn (IMH) | Brian's team built the agents control plane; audience for a follow-up demo |
| Chris Tava (Microsoft) | Works with IMH CloudOps and Brian's team; proposed the APIM/MCP → UC function approach |
| Joey Brakefield (Microsoft) | Data Solutions Engineer; Databricks and Fabric side; owns the BrakeKat tenant |

## Segment letters you'll see in notes
{widths: 900 6060 2400}
| Seg | What it proved | Oct 15 |
|---|---|---|
| A | Foundry agent → Genie MCP, per user (OAuth passthrough): 3 users saw different rows | Removed; talk track |
| B | Foundry agent → UC function MCP, per user: 3 users, Oct 12 | Removed; talk track |
| C | Foundry agent → APIM → UC function MCP as APIM's managed identity | Live, step 6 |
| D | Audit trail: APIM logs + Databricks Query History | Live, step 8 |
| E | No External Data Access needed: EDA off, agent still worked | Screenshots, step 9 |
| G | Genie space through APIM, agent identity | Removed; talk track |
| H | Gateway guardrails: row/size cap, rate limit, quota | Live, step 7 |
| I | Custom runtime (AKS stand-in) with an Entra token, no key | Live, step 10 |
| J | Databricks → APIM → Foundry model (`ai_query`) | Live, step 11 |
| K | Genie One MCP through Unity Gateway, per user (jay passed Oct 14) | Removed; talk track |

There is no segment F in this demo (it was a separate private-network test in another tenant, without Unity Catalog).

## Five lines to remember
1. Agents call Databricks through APIM; Unity Catalog alone decides rows and columns.
2. Four layers: the allow-list picks the tool, the function fixes the query, APIM limits volume, Unity Catalog decides the data.
3. No External Data Access: the function runs inside Databricks, and we proved it with EDA off.
4. On this path Databricks sees the agent's identity (Yun ④, machine to machine), not the caregiver's.
5. Not built: Yun ① and ②, the private network, AKS itself and the gateway app registration.
