param(
  [string]$PfxPath='C:\VEEV\certificado\ORGANIZACAO CARLTON LTDA16783003000189.pfx',
  [string]$CompanyId='298ead2d-118f-442e-8806-f94aa63b3021'
)
$ErrorActionPreference='Stop'
$parsedId=[guid]::Empty
if (-not [guid]::TryParse($CompanyId,[ref]$parsedId)) { throw 'Empresa deve ser UUID.' }
$CompanyId=$parsedId.ToString()
$bytes=[System.IO.File]::ReadAllBytes($PfxPath)
$encoded=[Convert]::ToBase64String($bytes)
$hash=(Get-FileHash -LiteralPath $PfxPath -Algorithm SHA256).Hash.ToLowerInvariant()
$destination='/var/lib/nfse/certificados/'+$CompanyId+'.pfx'
# Somente o PFX criptografado vai para a area de transferencia; nao sua senha.
# Noclobber impede substituir um certificado ja existente.
$command="(umask 077; set -o noclobber; printf '%s' '$encoded' | base64 -d > '$destination') && chmod 600 '$destination' && printf '%s\n' '$hash  $destination' | sha256sum -c -"
Set-Clipboard -Value $command
$bytes=$null
$encoded=$null
$command=$null
Write-Output 'Comando copiado. Cole no Bash do nfse-api no EasyPanel e pressione Enter.'
Write-Output 'O resultado esperado termina em .pfx: OK. A senha nao foi solicitada nem copiada.'
