param(
  [Parameter(Mandatory = $true)][string]$TestCompanyToken,
  [string]$OtherCompanyToken,
  [string]$BaseUrl = 'http://127.0.0.1:9000'
)
$ErrorActionPreference = 'Stop'
# Executar somente com empresa de testes: cria cadastros e altera seus padroes.
$headers = @{ Authorization = "Bearer $TestCompanyToken" }
function CallApi([string]$Method, [string]$Path, $Body) {
  $args = @{ Uri = "$BaseUrl/v1/$Path"; Method = $Method; Headers = $headers }
  if ($null -ne $Body) {
    $args.ContentType = 'application/json; charset=utf-8'
    $args.Body = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
  }
  Invoke-RestMethod @args
}
function Assert($Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
$settings = CallApi PATCH settings @{
  tax_regime = 'simples_nacional'; simples_percent = 6
  service_code = 'TESTE'; service_description = 'Servico de teste'
}
Assert ($settings.simples_percent -eq 6) 'Nao salvou 6%.'
# Documento sintetico para teste de formato, sem validacao cadastral fiscal.
$document = '9' + (Get-Random -Minimum 100000000 -Maximum 999999999).ToString() + '0'
$customer = CallApi POST customers @{ name = 'Teste automatizado'; document = $document }
$first = CallApi POST drafts @{ customer_id = $customer.id; amount_cents = 10000 }
Assert ($first.settings.simples_percent -eq 6) 'Nao herdou o padrao.'
$null = CallApi PATCH settings @{ simples_percent = 8 }
$second = CallApi POST drafts @{ customer_id = $customer.id; amount_cents = 10000 }
Assert ($second.settings.simples_percent -eq 8) 'Novo rascunho nao recebeu alteracao.'
Assert ($second.settings.service_code -eq 'TESTE') 'PATCH apagou configuracoes anteriores.'
$third = CallApi POST drafts @{
  customer_id = $customer.id; amount_cents = 10000; overrides = @{ simples_percent = 0 }
}
Assert ($third.settings.simples_percent -eq 0) 'Override zero nao respeitado.'
$defaults = CallApi GET settings $null
Assert ($defaults.simples_percent -eq 8) 'Override alterou o padrao.'
$anonymous = CallApi POST drafts @{ amount_cents = 10000 }
Assert ($null -eq $anonymous.customer_id) 'Nao aceitou tomador omitido.'
Assert ($anonymous.settings.simples_percent -eq 8) 'Rascunho sem tomador nao herdou configuracao.'
$anonymousNull = CallApi POST drafts @{ customer_id = $null; amount_cents = 10000 }
Assert ($null -eq $anonymousNull.customer_id) 'Nao aceitou tomador null.'
$drafts = @(CallApi GET drafts $null)
$saved = $drafts | Where-Object id -eq $first.id
Assert ($saved.settings.simples_percent -eq 6) 'Historico foi alterado.'
try {
  $null = CallApi PATCH settings @{ simples_percent = 101 }
  throw 'Aceitou aliquota invalida.'
} catch {
  if ($null -eq $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 422) { throw }
}
if ($OtherCompanyToken) {
  $headers.Authorization = "Bearer $OtherCompanyToken"
  try {
    $null = CallApi POST drafts @{ customer_id = $customer.id; amount_cents = 10000 }
    throw 'Aceitou cliente de outra empresa.'
  } catch {
    if ($null -eq $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 422) { throw }
  }
}
Write-Output 'OK: persistencia, alteracao, historico, override e validacao.'
