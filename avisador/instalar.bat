@echo off
chcp 65001 >nul
title Avisador de Treinamentos Mavaular - Instalacao
set "DEST=%LOCALAPPDATA%\TreinamentosMavaular"
echo Instalando o Avisador de Treinamentos Mavaular...
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0aviso-treinamentos.ps1" "%DEST%\aviso-treinamentos.ps1" >nul
copy /Y "%~dp0executar-oculto.vbs" "%DEST%\executar-oculto.vbs" >nul
powershell -NoProfile -Command "Unblock-File -Path '%DEST%\aviso-treinamentos.ps1'; Unblock-File -Path '%DEST%\executar-oculto.vbs'" >nul 2>&1

rem Confere a agenda a cada 30 minutos
schtasks /Create /F /SC MINUTE /MO 30 /TN "Avisador de Treinamentos Mavaular" /TR "wscript.exe \"%DEST%\executar-oculto.vbs\"" >nul
if errorlevel 1 (
  echo.
  echo Nao foi possivel criar a tarefa agendada do Windows.
  pause
  exit /b 1
)

rem Confere tambem ao entrar no Windows
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Avisador de Treinamentos Mavaular.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='\"%DEST%\executar-oculto.vbs\"'; $s.Save()" >nul 2>&1

rem Aviso de teste
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\aviso-treinamentos.ps1" -Teste
rem Primeira conferencia da agenda
wscript.exe "%DEST%\executar-oculto.vbs"

echo.
echo Pronto! Deve ter aparecido um aviso de teste no canto da tela.
echo A partir de agora o notebook avisa na vespera, no dia e 1 hora antes de cada treinamento.
echo.
pause
