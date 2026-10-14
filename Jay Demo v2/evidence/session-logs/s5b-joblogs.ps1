$ErrorActionPreference = 'Continue'
$cust = az monitor log-analytics workspace show -g rg-ai -n law-imh-uc-66zpmtcbvhe7w --query customerId -o tsv
"law=$cust"
$q = 'union isfuzzy=true (ContainerAppConsoleLogs_CL | project TimeGenerated, src="console", msg=Log_s, job=ContainerJobName_s), (ContainerAppSystemLogs_CL | project TimeGenerated, src="system", msg=Log_s, job=ContainerJobName_s) | where TimeGenerated > ago(2h) | order by TimeGenerated asc | take 80'
$body = @{ query = $q } | ConvertTo-Json -Compress
$tmp = Join-Path $env:TEMP 'laq.json'
Set-Content -LiteralPath $tmp -Value $body -Encoding ascii
for ($i = 0; $i -lt 12; $i++) {
  $r = az rest --method post --url "https://api.loganalytics.io/v1/workspaces/$cust/query" --resource https://api.loganalytics.io --body "@$tmp" -o json | ConvertFrom-Json
  $rows = $r.tables[0].rows
  if ($rows.Count -gt 0) { break }
  "no rows yet; waiting"; Start-Sleep 30
}
foreach ($row in $rows) { "$($row[0]) [$($row[1])] $($row[3]): $($row[2])" }
Remove-Item $tmp
'S5B-DONE'
