# UC agent gateway — deployable IaC

Everything we built by hand in BrakeKat, as code IMH can run in its own dev, test and prod environments.

```
Agent (Foundry / Copilot Studio / custom Python in AKS or Container Apps)
  └─ APIM  (subscription key or Entra token, rate limit, quota, row/size cap, correlation ID, Log Analytics)
       └─ user-assigned managed identity → Databricks service principal
            └─ Databricks managed MCP (/uc → UC functions, /genie → Genie space)
                 └─ Unity Catalog (row filter + column masks decide what comes back)

Databricks (ai_query, agents) ─ external-model serving endpoint + AI Gateway
  └─ APIM /aoai (key, rate limit, llm-token-limit) ─ managed identity ─ Foundry model (gpt-4.1)
```

Unity Catalog stays the only data-governance layer. APIM never filters data. It only adds rate limits, quotas,
a row/size cap and caller identity checks.

## APIs on the gateway

| Path | Caller auth | Policy | Proves |
|---|---|---|---|
| `/uc/mcp` | APIM key | 30 calls/min per key | UC functions via the APIM managed identity |
| `/genie/mcp` | APIM key | 30 calls/min per key | Genie space via the same managed identity (async `query_space_*` → `poll_response_*`) |
| `/uc-limited/mcp` | APIM key | 3 `tools/call`/min, 200/day quota, **>5 rows or >20 KB blocked** (MCP `isError` + `x-imh-gateway-block` header) | Gateway guardrails on result size and rate |
| `/uc-entra/mcp` | **Entra token** (no key) | `validate-azure-ad-token`: tenant + audience + client app allow-list; rate limit per caller app ID | Runtime identity, no shared secret |
| `/aoai/*` | APIM key in `api-key` header | 30 calls/min + `llm-token-limit` 20k TPM; managed identity → Foundry | Databricks → APIM → Foundry model |

Policy XML lives in `azure/policy-*.xml` with `__TOKEN__` placeholders. Terraform reads them with `file()` +
`replace()`. `main.bicep` still carries the same policies inline (that is the version deployed and tested in
BrakeKat); switching it to `loadTextContent('../policy-*.xml')` is a pending refactor. Until then, change a policy in
both places. `azure/policy.xml.tftpl` is no longer used and can be deleted.

## What is in here

| Folder | Tool | Creates |
|---|---|---|
| `azure/bicep/main.bicep` | Bicep | APIM managed identity, runtime managed identity, Log Analytics, APIM (BasicV2 or StandardV2), the five APIs above with policies, one key per key-based API, gateway logs, Cognitive Services OpenAI User for APIM on the model account, key-based Foundry connections per MCP API. |
| `azure/bicep/runtime.bicep` | Bicep | Container Apps environment + manual job `job-imh-uc-agent` running `python_mcp_client.py` as the runtime managed identity against `/uc-entra/mcp`. Stands in for AKS. |
| `azure/terraform/` | Terraform (azurerm + azapi) | Same as both Bicep files (`runtime.tf` = runtime.bicep). Choose Bicep or Terraform. |
| `azure/policy-*.xml` | — | Shared APIM policies (`mcp-key`, `mcp-limited`, `mcp-entra`, `model`). |
| `databricks/terraform/` | Terraform (databricks) | Account groups, managed identity as a service principal in the agent group, workspace assignment, UC grants, optional warehouse ACL, optional OAuth app, SQL file + run-once job (table, row filter, masks, `get_patients`, `get_patients_limited`), secret scope + **external-model serving endpoint through APIM `/aoai` with AI Gateway** (`model_gateway.tf`). |
| `databricks/Setup-DatabricksSide.ps1` | PowerShell + Databricks CLI | One-shot alternative to the Databricks Terraform for the BrakeKat demo: runs `get_patients_limited.sql`, stores the APIM key in a secret scope, creates the serving endpoint and tests it with REST and `ai_query`. |
| `foundry/create_agents.py` | Python (azure-ai-projects 2.x) | Foundry prompt agent with the MCP tool pointing at APIM through a project connection. `--kind uc|genie`, `--ask "<question>"` to invoke it. |
| `clients/python_mcp_client.py` | Python (stdlib only) | Custom-harness client. Auth: APIM key, `azcli`, managed identity (`mi`) or AKS workload identity (`workload`). `--repeat N` shows 429s. |

Both `azure/` options produce the same resource names, so a Bicep-built stack can be moved to Terraform with
`terraform import` (see below).

## Deploy order

1. **Azure gateway**: Bicep or Terraform. Note the `umiClientId`, `entraAudience` and `modelGatewayUrl` outputs.
   - Bicep: `az deployment group create -g <rg> -n uc-agent-gateway -p azure/bicep/<env>.bicepparam`, then
     `az deployment group create -g <rg> -n imh-uc-runtime -f azure/bicep/runtime.bicep -p apimName=<apimName> logAnalyticsWorkspaceName=<law> runtimeUmiName=<runtimeUmiName> gatewayAudience=<entraAudience>`
   - Terraform: `cd azure/terraform; terraform init; terraform apply -var-file=<env>.tfvars` (includes the runtime).
2. **Databricks**: set `umi_client_id` from step 1, put the `/aoai` key in an env var
   (`$env:TF_VAR_apim_model_key = az rest --method post --url <apim id>/subscriptions/databricks-ai-gateway/listSecrets?api-version=2024-05-01 --query primaryKey -o tsv`),
   then `cd databricks/terraform; terraform init; terraform apply -var-file=<env>.tfvars`.
   On a fresh workspace with `deploy_uc_objects = true`, run the setup job once:
   `databricks jobs run-now <setup_job_id>`. For BrakeKat, `databricks/Setup-DatabricksSide.ps1` does the same
   Databricks-side steps without Terraform.
3. **Foundry agents** (optional): `pip install -r foundry/requirements.txt`, then
   `python foundry/create_agents.py --endpoint <project endpoint> --mcp-url <url> --connection <connection> [--kind genie] --ask "<question>"`.
   For the UC tool add `--allowed-tools <catalog>__<schema>__get_patients`: the schema also exposes
   `get_patients_limited`, and an agent that picks it bypasses the APIM row cap.
4. **Smoke tests**: see below.

Both Terraform providers sign in with `az login` (`auth_type = "azure-cli"`). In a pipeline, use a workload-identity
service connection instead.

## Smoke tests (keys stay in env vars)

```powershell
$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$id   = "/subscriptions/<sub>/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/$apim"
function Key($name) { az rest --method post --url "https://management.azure.com$id/subscriptions/$name/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv }

# 1. UC functions: 4 SLC rows, masked
$env:APIM_SUBSCRIPTION_KEY = Key foundry-imh-uc-agent; $env:APIM_MCP_URL = "https://$apim.azure-api.net/uc/mcp"
python clients/python_mcp_client.py --facility SLC

# 2. Row cap: all facilities = 12 rows > 5 -> "Blocked by gateway policy", header x-imh-gateway-block: row-limit 12>5
$env:APIM_SUBSCRIPTION_KEY = Key imh-uc-limited-client; $env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-limited/mcp"
$env:MCP_ARGS = '{"fac": null}'; python clients/python_mcp_client.py; Remove-Item Env:MCP_ARGS

# 3. Rate limit: calls 4+ in a minute -> HTTP 429
python clients/python_mcp_client.py --facility SLC --repeat 5

# 4. Entra: your own token is refused (client app not on the allow-list) -> 401
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-entra/mcp"
python clients/python_mcp_client.py --auth azcli --audience https://management.azure.com --facility SLC

# 5. Entra positive: the runtime job (its managed identity is on the allow-list) -> 4 SLC rows in the job logs
az containerapp job start -g rg-ai -n job-imh-uc-agent
```

Log Analytics (`law-imh-uc-…`):

```kusto
// Every gateway call. CorrelationId = APIM request ID = the x-imh-correlation-id header the client prints.
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, ApiId, ApimSubscriptionId, Method, Url, ResponseCode, BackendResponseCode, CorrelationId, TotalTime
| order by TimeGenerated desc

// Runtime job output
ContainerAppConsoleLogs_CL | where ContainerJobName_s == 'job-imh-uc-agent' | project TimeGenerated, Log_s | order by TimeGenerated desc
```

## BrakeKat constraints and interim choices

| Yun's design | BrakeKat | Why | At IMH |
|---|---|---|---|
| Agent runtime on **AKS** with workload identity | **Container Apps job** with a user-assigned managed identity | `Microsoft.ContainerService` isn't registered in the BrakeKat subscription and the guest account can't register providers | AKS + workload identity: federate `umi-imh-uc-runtime` to the pod's service account, run the client with `--auth workload`. Same APIM API and policy. |
| Entra token for an **app registration** (`api://imh-uc-gateway`) | Audience `https://management.azure.com`, locked down by the client app allow-list (only the runtime managed identity's app ID) | The guest can't create app registrations, and Entra refuses tokens whose audience is a managed identity (AADSTS100040) | Register `imh-uc-gateway` (expose an API / app role), set `gatewayAudience = 'api://<appId>'`, add the agent identities to `allowedClientAppIds`, require the app role. ARM-audience tokens can be replayed to ARM, so don't keep the interim audience in production. |
| Private Link end to end | Public endpoints | Would disrupt the working demo | See Networking. |

## Still manual (no API or provider support yet)

| Step | Why manual | Where |
|---|---|---|
| Enable **Managed MCP Servers** preview | Workspace preview toggle, no Terraform resource | Workspace → Admin → Previews |
| Create the **Genie space** and share it with the groups | No `databricks_genie_space` resource | Workspace → Genie |
| Per-user (OAuth passthrough) Foundry connection | Redirect URI is shown only while adding the connection in Foundry | Foundry → Tools → Azure Databricks Genie / custom MCP OAuth; Databricks account → App connections |
| Warehouse **Can use** on a shared warehouse | `databricks_permissions` replaces every ACL on the warehouse; default is off | Warehouse → Permissions |
| Catalog on a metastore with no root storage | Needs an external location path; set `create_catalog = true` + `catalog_storage_root` or create it in the UI | Catalog → Create catalog |
| Users and group membership | At IMH, groups are SCIM-synced from Entra ID (`create_groups = false`) | Entra ID / SCIM |
| Foundry agent | Agent versions are data-plane objects, not ARM resources | `foundry/create_agents.py` |
| Gateway app registration (`api://imh-uc-gateway`) | Needs an Entra admin; BrakeKat guest can't create apps | Entra ID → App registrations, then `gatewayAudience` |
| `get_patients_limited` + serving endpoint in BrakeKat | The guest account gets 403 on the workspace; Jay runs them as `jay@brakekat.com` (done 2026-10-13) | `databricks/Setup-DatabricksSide.ps1` |

## Secrets and state

- No secret is written to a file. APIM generates the subscription keys; Bicep passes the key straight into the
  Foundry connection with `listSecrets()`.
- **Terraform state does hold secrets**: the APIM subscription keys (Azure) and the OAuth client secret if
  `create_oauth_app = true` (Databricks). Use a remote `azurerm` backend with RBAC and encryption, never local state
  in OneDrive or a repo. Copy `terraform.tfvars.example` to `terraform.tfvars` and keep it out of git.
- For the Python client in AKS, mount the key from Key Vault (CSI driver) as an environment variable.

## Mapping to IMH

| BrakeKat demo | IMH |
|---|---|
| One APIM in `rg-ai` | Your central APIM per dev/test/prod resource group. Use the Terraform APIs/policies/subscriptions against the existing instance (drop `azurerm_api_management` or import it). |
| One managed identity `umi-imh-uc-agent` in `imh_analyst` | One managed identity per agent or per data domain, each in its own SCIM-synced group. The group decides the rows and masks. |
| Key-based Foundry connection | Same, or Entra-based auth (`user-entra-token` / `project-managed-identity`) once validated for Databricks. |
| Public endpoints | Private Link + VNet integration — see Networking. |
| `imh_demo.clinical.patients` (synthetic) | Your real UC tables and functions; the grants and the MCP URL pattern stay the same. |

The identity choice is the main design decision: with the APIM managed identity, **every caller of that
subscription key gets the managed identity's data access**. Use the per-user OAuth path when the person must
be the one Databricks sees in Query History.

## Networking (not built in BrakeKat)

BrakeKat runs on public endpoints. A private deployment needs:

1. Databricks front-end Private Link (VNet-injected workspace) with the `privatelink.azuredatabricks.net` DNS zone.
2. APIM able to reach it: `apim_sku = StandardV2` with outbound VNet integration, or APIM Premium/Developer in
   internal VNet mode.
3. Foundry agents with private networking (an agent subnet) that can resolve and reach the private APIM.
4. Private DNS linked to every VNet in the path.

This is the path that was proven earlier to a Databricks warehouse but **not yet with a Unity Catalog metastore**.
Validate it in an IMH environment before relying on it.

## Moving the BrakeKat stack to Terraform (import)

Set `name_suffix = "66zpmtcbvhe7w"` (the Bicep `uniqueString`), then for example:

```
terraform import azurerm_user_assigned_identity.agent /subscriptions/<sub>/resourceGroups/rg-ai/providers/Microsoft.ManagedIdentity/userAssignedIdentities/umi-imh-uc-agent
terraform import azurerm_api_management.apim /subscriptions/<sub>/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/apim-imh-uc-66zpmtcbvhe7w
terraform import 'azurerm_api_management_api.mcp["uc"]' /subscriptions/<sub>/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/apim-imh-uc-66zpmtcbvhe7w/apis/imh-uc-functions-mcp;rev=1
```

Repeat for the operations, policies, subscriptions, the diagnostic setting and the Log Analytics workspace, then
run `terraform plan` and confirm it shows no changes. For Databricks, import the existing groups
(`databricks_group.this["analyst"]` etc.) and the service principal, or set `create_groups = false`.

## Validation done

Deployed to BrakeKat `rg-ai` with Bicep (`main.bicep` + `runtime.bicep`) and tested:

| Test | Result |
|---|---|
| `/uc/mcp` `get_patients` SLC (key) | 200, 4 SLC rows, names REDACTED, SSN masked |
| `/genie/mcp` + Foundry agent `imh-genie-apim-umi-agent` | per-facility counts + generated SQL |
| `/uc-limited/mcp` SLC / all facilities / 4th call in a minute | 4 rows / `isError` "Blocked by gateway policy" + `x-imh-gateway-block: row-limit 12>5` / 429 |
| Foundry agent `imh-uc-limited-agent` on an all-facility ask | relays the block and asks the user to narrow |
| `/uc-entra/mcp` with Jay's az cli token (not on the allow-list) | 401 |
| Container Apps job `job-imh-uc-agent` (runtime managed identity, no key) | Succeeded, 4 SLC rows, HTTP 200 |
| `/aoai` chat completion through APIM managed identity | 200 "gateway ok" |
| `Setup-DatabricksSide.ps1` as `jay@brakekat.com` (2026-10-13): `get_patients_limited` | 5 rows by default, 10 when 50 are asked for (of 12) |
| Same run: endpoint `imh-foundry-gpt41-via-apim` (AI Gateway usage tracking, 60 calls/min) → `/aoai` | READY; REST "databricks to foundry via apim ok"; `ai_query` answered |

Not yet validated (the run was blocked by a local tooling outage, not by a test failure):

- `terraform init -backend=false && terraform validate && terraform fmt -check` for `azure/terraform` and
  `databricks/terraform` after the parity changes (shared policy files, limited/entra/model APIs, `runtime.tf`,
  `model_gateway.tf`). Run these before using Terraform; watch `azurerm_container_app_job` and the databricks
  `ai_gateway` block, which are the most version-sensitive.
- `model_gateway.tf` and the setup job's `uc_objects.sql.tftpl` (the script covered the same steps in BrakeKat).
- Not applied anywhere: the Terraform.
