param(
  [Parameter(Mandatory=$true)][string]$DraftId,
  [Parameter(Mandatory=$true)][string]$IssuedAt,
  [Parameter(Mandatory=$true)][string]$Competence,
  [string]$BaseUrl='https://nfse-nfse-api.0piict.easypanel.host'
)
$ErrorActionPreference='Stop'
$guidCheck=[guid]::Empty
if (-not [guid]::TryParse($DraftId,[ref]$guidCheck)) { throw 'DraftId deve ser UUID.' }
$secret=Read-Host 'Chave da API CARLTON (oculta)' -AsSecureString
$credential=New-Object System.Management.Automation.PSCredential('api',$secret)
$token=$credential.GetNetworkCredential().Password -replace '\s',''
if ($token -notmatch '^[0-9a-fA-F]{64}$') { throw 'Chave invalida.' }
$headers=@{Authorization='Bearer '+$token}
try {
  $body=@{issued_at=$IssuedAt;competence=$Competence} | ConvertTo-Json -Compress
  $attempt=Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd('/')+'/v1/drafts/'+$DraftId+'/emit-homologation') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
  $attempt | ConvertTo-Json -Depth 12
  Write-Output 'Nao repita com outro rascunho para a mesma operacao sem conferir o estado desta tentativa.'
} finally {
  $token=$null
  $headers.Clear()
  $credential=$null
}
