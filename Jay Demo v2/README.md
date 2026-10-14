# Jay Demo v2 — IMH Option 2 (UC Functions + MCP + API Management)

Demo for the Intermountain Health onsite (Oct 15, 2026). Runs in the BrakeKat demo tenant (West US 3) with synthetic data only.

| Folder / file | What it is |
|---|---|
| `dry-run-agent.md` | Dry-run playbook: run of show, what to say, troubleshooting |
| `IMH-Option2-Dry-Run-and-Workflow.docx` | End-to-end workflow doc (built from `build/content/*.md` by `build/build-docx.mjs`) |
| `infra/uc-agent-gateway/` | IaC: APIM policies, Bicep, Terraform (Azure + Databricks), Databricks setup, Foundry agent script, MCP client |
| `infra/brakekat-apim-umi/` | APIM + user-assigned managed identity deployment and test scripts |
| `infra/sql/` | Synthetic patient fixtures |
| `evidence/` | Proof runs, Foundry snapshot before cleanup, session logs and scripts |
| `images/` | Architecture diagrams and screenshots of each proof |
| `resources/` | Older Oct 13 notes (not the source of truth) |

Secrets are not stored here. Keys live in Foundry project connections, Databricks secret scopes and Key Vault.
