$ErrorActionPreference = 'Continue'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$fd = "$infra\uc-agent-gateway\foundry"
$sub = '9bbee190-dc61-4c58-ab47-1275cb04018f'
$apim = 'apim-imh-uc-66zpmtcbvhe7w'

'=== Azure AI User on aif-wu3 for the signed-in user ==='
$aif = az cognitiveservices account show -g rg-ai -n aif-wu3 --query id -o tsv
$me = az ad signed-in-user show --query id -o tsv 2>$null
if (-not $me) { $me = 'ddc2fa17-eab9-410b-a995-bb6bf1de96f3' }
az role assignment create --assignee-object-id $me --assignee-principal-type User --role 53ca6127-db72-4b80-b1b0-d745d6d5456d --scope $aif --query roleDefinitionName -o tsv
"role exit $LASTEXITCODE"

'=== venv (outside OneDrive) ==='
$py = 'C:\Users\jaypadhya\AppData\Roaming\uv\python\cpython-3.12.13-windows-x86_64-none\python.exe'
$venv = Join-Path $env:LOCALAPPDATA 'ucgw-venv'
if (-not (Test-Path "$venv\Scripts\python.exe")) { & $py -m venv $venv }
& "$venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check -r "$fd\requirements.txt"
"pip exit $LASTEXITCODE"
& "$venv\Scripts\python.exe" -c "import azure.ai.projects as p; print('azure-ai-projects', p.__version__)"

$env:FOUNDRY_PROJECT_ENDPOINT = 'https://aif-wu3.services.ai.azure.com/api/projects/proj-imh-uc-demo'
'=== Genie agent via APIM ==='
& "$venv\Scripts\python.exe" "$fd\create_agents.py" --kind genie --mcp-url "https://$apim.azure-api.net/genie/mcp" --connection genie-via-apim-umi-iac --ask "How many patients are there per facility? Show the SQL."
'=== Limited UC agent via APIM ==='
& "$venv\Scripts\python.exe" "$fd\create_agents.py" --kind uc --agent-name imh-uc-limited-agent --mcp-url "https://$apim.azure-api.net/uc-limited/mcp" --connection uc-limited-via-apim-umi-iac --ask "Show me all patients across every facility."
'S6-DONE'
