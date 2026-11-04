@echo off
chcp 65001 >nul
setlocal EnableExtensions
title Avisador de Treinamentos Mavaular - Instalacao
set "ORIGEM=%~dp0"
if "%ORIGEM:~-1%"=="\" set "ORIGEM=%ORIGEM:~0,-1%"
set "PS1URL=https://treinamentos-mavaular.netlify.app/avisador/aviso-treinamentos.ps1"
echo Instalando o Avisador de Treinamentos Mavaular...

rem Tenta instalar em: AppData, depois Documentos, depois a propria pasta extraida
set "DEST="
call :preparar "%LOCALAPPDATA%\TreinamentosMavaular"
if not defined DEST call :preparar "%USERPROFILE%\Documents\Avisador de Treinamentos"
if not defined DEST if exist "%ORIGEM%\aviso-treinamentos.ps1" call :usar_origem
if not defined DEST (
  echo.
  echo O Windows bloqueou a instalacao em todas as pastas tentadas.
  echo Provavelmente o antivirus ou uma politica da empresa impede rodar scripts.
  echo Mostre esta mensagem ao suporte de TI.
  pause
  exit /b 1
)
echo Pasta do avisador: %DEST%

rem Arquivo que roda o avisador sem abrir janela
> "%DEST%\executar-oculto.vbs" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%DEST%\executar-oculto.vbs" echo pasta = fso.GetParentFolderName(WScript.ScriptFullName)
>> "%DEST%\executar-oculto.vbs" echo CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ ^& pasta ^& "\aviso-treinamentos.ps1""", 0, False
powershell -NoProfile -Command "Unblock-File -Path '%DEST%\aviso-treinamentos.ps1'" >nul 2>&1

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

rem Aviso de teste e primeira conferencia
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\aviso-treinamentos.ps1" -Teste
if errorlevel 1 echo Atencao: o aviso de teste nao pode ser exibido.
wscript.exe "%DEST%\executar-oculto.vbs"

echo.
echo Pronto! Deve ter aparecido um aviso de teste no canto da tela.
if /I "%DEST%"=="%ORIGEM%" echo IMPORTANTE: nao apague esta pasta - o avisador roda a partir dela.
echo A partir de agora o notebook avisa na vespera, no dia e 1 hora antes de cada treinamento.
echo.
pause
exit /b 0

:preparar
set "ALVO=%~1"
if not exist "%ALVO%" mkdir "%ALVO%" 2>nul
if not exist "%ALVO%" exit /b 1
attrib -r -s -h "%ALVO%\*" >nul 2>&1
del /F /Q "%ALVO%\aviso-treinamentos.ps1" "%ALVO%\executar-oculto.vbs" >nul 2>&1
if exist "%ORIGEM%\aviso-treinamentos.ps1" (
  copy /Y "%ORIGEM%\aviso-treinamentos.ps1" "%ALVO%\aviso-treinamentos.ps1" >nul 2>&1
) else (
  powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; (New-Object Net.WebClient).DownloadFile('%PS1URL%', '%ALVO%\aviso-treinamentos.ps1')" >nul 2>&1
)
if not exist "%ALVO%\aviso-treinamentos.ps1" exit /b 1
(echo teste) > "%ALVO%\executar-oculto.vbs" 2>nul
if not exist "%ALVO%\executar-oculto.vbs" exit /b 1
set "DEST=%ALVO%"
exit /b 0

:usar_origem
(echo teste) > "%ORIGEM%\executar-oculto.vbs" 2>nul
if not exist "%ORIGEM%\executar-oculto.vbs" exit /b 1
set "DEST=%ORIGEM%"
exit /b 0
