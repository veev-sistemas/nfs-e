param(
  [string]$BaseUrl = 'https://nfse-nfse-api.0piict.easypanel.host',
  [string]$XmlPath = '\\wsl.localhost\Ubuntu\home\veev\nfse-testes\consultas\consulta-zqNt87qm\nfse-consultada.xml'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $XmlPath)) { throw 'XML nao encontrado. Informe -XmlPath com o caminho do XML recuperado na consulta.' }
$xmlContent = [IO.File]::ReadAllText($XmlPath)
$key = Read-Host 'Cole a chave da API da empresa CARLTON (64 caracteres)' -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential('api', $key)
$token = $credential.GetNetworkCredential().Password -replace '\s',''
if ($token -notmatch '^[0-9a-fA-F]{64}$') { throw 'Formato da chave de API invalido.' }
$headers = @{ Authorization = 'Bearer ' + $token }
try {
  # Nota de ensaio externa: nao associar a um rascunho ficticio da API.
  $body = @{ xml = $xmlContent } | ConvertTo-Json -Depth 4 -Compress
  $invoice = Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/') + '/v1/invoices/import-homologation') -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $savedXml = Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl.TrimEnd('/') + '/v1/invoices/' + $invoice.id + '/xml') -Headers $headers
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($xmlContent))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Dispose() }
  if ($hash -ne $invoice.xml_sha256) { throw 'Hash do XML armazenado diverge do arquivo local.' }
  if ($savedXml.Content -ne $xmlContent) { throw 'XML recuperado diverge do arquivo enviado.' }
  $invoice | Select-Object id,environment,access_key,invoice_number,amount_cents,status,draft_id | Format-List
  Write-Output 'OK: XML importado, recuperado e conferido. Nenhuma nota emitida.'
} finally {
  $token = $null
  $headers.Clear()
  $credential = $null
}
