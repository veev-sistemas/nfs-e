@echo off
cd /d "%~dp0"
if not exist "%~dp0NfseBackend.exe" (
  echo Compile NfseBackend.dproj no Delphi antes de executar.
  pause
  exit /b 1
)
"%~dp0NfseBackend.exe"
echo.
echo O servidor foi encerrado. Veja a mensagem acima.
pause
