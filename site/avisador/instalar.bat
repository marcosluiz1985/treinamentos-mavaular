@echo off
chcp 65001 >nul
title Avisador de Treinamentos Mavaular - Instalacao
set "DEST=%LOCALAPPDATA%\TreinamentosMavaular"
set "PS1URL=https://treinamentos-mavaular.netlify.app/avisador/aviso-treinamentos.ps1"
echo Instalando o Avisador de Treinamentos Mavaular...
if not exist "%DEST%" mkdir "%DEST%"

rem 1. Programa do avisador: usa o da pasta, ou baixa do portal
if exist "%~dp0aviso-treinamentos.ps1" (
  copy /Y "%~dp0aviso-treinamentos.ps1" "%DEST%\aviso-treinamentos.ps1" >nul
) else (
  powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; (New-Object Net.WebClient).DownloadFile('%PS1URL%', '%DEST%\aviso-treinamentos.ps1')"
)
if not exist "%DEST%\aviso-treinamentos.ps1" (
  echo.
  echo Nao foi possivel obter o avisador. Verifique a internet e tente de novo.
  pause
  exit /b 1
)

rem 2. Arquivo que roda o avisador sem abrir janela
> "%DEST%\executar-oculto.vbs" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%DEST%\executar-oculto.vbs" echo pasta = fso.GetParentFolderName(WScript.ScriptFullName)
>> "%DEST%\executar-oculto.vbs" echo CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ ^& pasta ^& "\aviso-treinamentos.ps1""", 0, False
powershell -NoProfile -Command "Unblock-File -Path '%DEST%\aviso-treinamentos.ps1'" >nul 2>&1

rem 3. Confere a agenda a cada 30 minutos
schtasks /Create /F /SC MINUTE /MO 30 /TN "Avisador de Treinamentos Mavaular" /TR "wscript.exe \"%DEST%\executar-oculto.vbs\"" >nul
if errorlevel 1 (
  echo.
  echo Nao foi possivel criar a tarefa agendada do Windows.
  pause
  exit /b 1
)

rem 4. Confere tambem ao entrar no Windows
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Avisador de Treinamentos Mavaular.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='\"%DEST%\executar-oculto.vbs\"'; $s.Save()" >nul 2>&1

rem 5. Aviso de teste e primeira conferencia
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\aviso-treinamentos.ps1" -Teste
wscript.exe "%DEST%\executar-oculto.vbs"

echo.
echo Pronto! Deve ter aparecido um aviso de teste no canto da tela.
echo A partir de agora o notebook avisa na vespera, no dia e 1 hora antes de cada treinamento.
echo.
pause
