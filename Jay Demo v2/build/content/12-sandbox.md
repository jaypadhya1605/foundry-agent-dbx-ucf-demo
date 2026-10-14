# 12. IMH sandbox: the 1:15–3:00 hands-on {#s12}

**Workspace:** `https://adb-7405605832508369.9.azuredatabricks.net` (Peter Jones; group `DPG_FOUNDRY_CONNECTION_TEST`). Non-PHI data only.

> SAY: Let's stand up the same pattern in your sandbox: one UC function, APIM's identity as a service principal, and one APIM API. Unity Catalog stays the only place the rules live.

## Checklist
1. Managed MCP servers enabled (workspace Admin → Previews).
2. Serverless compute allowed in the workspace (MCP tool calls run on it).
3. A non-PHI table to point at.
4. One UC table function on that table (pattern below).
5. APIM's managed identity added as a service principal, with USE CATALOG, USE SCHEMA, SELECT and EXECUTE.
6. An APIM API → `/api/2.0/mcp/functions/<catalog>/<schema>` with the policy in Appendix C.1 (`policy-mcp-key.xml`).
7. Test with `infra\uc-agent-gateway\clients\python_mcp_client.py` (Appendix D shows the calls).

> NOTE: `apim-ih-ent-eap-dev` has Databricks REST only; MCP on it is in cyber review (Yun, Oct 14). If it hasn't cleared, do items 1–5, test the function in the SQL editor, and leave the APIM API as a follow-up.

## Function and grants pattern
Same shape as `get_patients` (Appendix B). Replace each `<...>` placeholder. A service principal is named by its application (client) ID.

```sql
CREATE OR REPLACE FUNCTION <catalog>.<schema>.get_rows(
  p_value STRING DEFAULT NULL COMMENT 'Filter value. NULL = all rows the caller may see.')
RETURNS TABLE (<col1> STRING, <col2> STRING)
COMMENT 'Rows visible to the caller under Unity Catalog rules.'
RETURN
  SELECT <col1>, <col2>
  FROM <catalog>.<schema>.<table>
  WHERE p_value IS NULL OR <col1> = p_value;

GRANT USE CATALOG ON CATALOG <catalog> TO `<apim-identity-application-id>`;
GRANT USE SCHEMA ON SCHEMA <catalog>.<schema> TO `<apim-identity-application-id>`;
GRANT SELECT ON TABLE <catalog>.<schema>.<table> TO `<apim-identity-application-id>`;
GRANT EXECUTE ON FUNCTION <catalog>.<schema>.get_rows TO `<apim-identity-application-id>`;
```

## What to write down for the 3:30 follow-ups
- What worked and what was blocked (network, preview, permissions, cyber review), with owners and dates for MCP on `apim-ih-ent-eap-dev`, Private Link + NCC, the gateway app registration and AKS workload identity.
- Whether Brian, Andy and Shawn want their own demo of this path.
