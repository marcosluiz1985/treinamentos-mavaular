@echo off
chcp 65001 >nul
setlocal EnableExtensions
title Avisador de Treinamentos Mavaular - Instalacao
set "ORIGEM=%~dp0"
if "%ORIGEM:~-1%"=="\" set "ORIGEM=%ORIGEM:~0,-1%"
set "PS1URL=https://treinamentos-mavaular.netlify.app/avisador/aviso-treinamentos.ps1"
set "TAREFA=Avisador de Treinamentos Mavaular"
echo Instalando o Avisador de Treinamentos Mavaular...

rem Remove a tarefa agendada de instalacoes anteriores (se existir)
schtasks /Delete /F /TN "%TAREFA%" >nul 2>&1

rem Escolhe a pasta: Documentos, AppData ou a propria pasta extraida
set "DEST="
call :preparar "%USERPROFILE%\Documents\Avisador de Treinamentos"
if not defined DEST call :preparar "%LOCALAPPDATA%\TreinamentosMavaular"
if not defined DEST if exist "%ORIGEM%\aviso-treinamentos.ps1" call :usar_origem
if not defined DEST (
  echo.
  echo O Windows bloqueou a instalacao em todas as pastas tentadas.
  echo Mostre esta mensagem ao suporte de TI.
  pause
  exit /b 1
)
echo Pasta do avisador: %DEST%

rem Arquivo que inicia o avisador sem abrir janela (modo continuo)
> "%DEST%\executar-oculto.vbs" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%DEST%\executar-oculto.vbs" echo pasta = fso.GetParentFolderName(WScript.ScriptFullName)
>> "%DEST%\executar-oculto.vbs" echo CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ ^& pasta ^& "\aviso-treinamentos.ps1"" -Laco", 0, False
powershell -NoProfile -Command "Unblock-File -Path '%DEST%\aviso-treinamentos.ps1'" >nul 2>&1

rem Inicia junto com o Windows (registro do usuario; se bloqueado, pasta Inicializar)
set "INICIO_OK="
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "AvisadorTreinamentosMavaular" /t REG_SZ /d "wscript.exe \"%DEST%\executar-oculto.vbs\"" /f >nul 2>&1
if not errorlevel 1 set "INICIO_OK=1"
if not defined INICIO_OK (
  set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
  call :startup_vbs
)
if not defined INICIO_OK (
  echo.
  echo Nao foi possivel colocar o avisador para iniciar com o Windows.
  echo Ele vai funcionar agora, mas depois de reiniciar o notebook
  echo sera preciso abrir "executar-oculto.vbs" na pasta: %DEST%
)

rem Aviso de teste e inicio imediato
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\aviso-treinamentos.ps1" -Teste
if errorlevel 1 echo Atencao: o aviso de teste nao pode ser exibido.
wscript.exe "%DEST%\executar-oculto.vbs"

echo.
echo Pronto! Deve ter aparecido um aviso de teste no canto da tela.
if /I "%DEST%"=="%ORIGEM%" echo IMPORTANTE: nao apague esta pasta - o avisador roda a partir dela.
schtasks /Query /TN "%TAREFA%" >nul 2>&1
if not errorlevel 1 (
  echo.
  echo ATENCAO: ficou uma tarefa antiga que o Windows nao deixou remover.
  echo Abra o "Agendador de Tarefas", procure "%TAREFA%" e exclua.
)
echo.
echo O avisador ja esta rodando e vai iniciar sozinho sempre que o Windows ligar.
echo Ele avisa na vespera, no dia e 1 hora antes de cada treinamento.
echo.
pause
exit /b 0

:preparar
set "ALVO=%~1"
if not exist "%ALVO%" mkdir "%ALVO%" 2>nul
if not exist "%ALVO%" exit /b 1
attrib -r -s -h "%ALVO%\*" >nul 2>&1
if /I "%ALVO%"=="%ORIGEM%" goto :preparar_ok
del /F /Q "%ALVO%\aviso-treinamentos.ps1" >nul 2>&1
if exist "%ORIGEM%\aviso-treinamentos.ps1" (
  copy /Y "%ORIGEM%\aviso-treinamentos.ps1" "%ALVO%\aviso-treinamentos.ps1" >nul 2>&1
) else (
  powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; (New-Object Net.WebClient).DownloadFile('%PS1URL%', '%ALVO%\aviso-treinamentos.ps1')" >nul 2>&1
)
:preparar_ok
if not exist "%ALVO%\aviso-treinamentos.ps1" exit /b 1
(echo teste) > "%ALVO%\executar-oculto.vbs" 2>nul
if not exist "%ALVO%\executar-oculto.vbs" exit /b 1
set "DEST=%ALVO%"
exit /b 0

:startup_vbs
if not exist "%STARTUP%" mkdir "%STARTUP%" 2>nul
> "%STARTUP%\Avisador de Treinamentos Mavaular.vbs" echo CreateObject("WScript.Shell").Run "wscript.exe ""%DEST%\executar-oculto.vbs""", 0, False
if exist "%STARTUP%\Avisador de Treinamentos Mavaular.vbs" set "INICIO_OK=1"
exit /b 0

:usar_origem
(echo teste) > "%ORIGEM%\executar-oculto.vbs" 2>nul
if not exist "%ORIGEM%\executar-oculto.vbs" exit /b 1
set "DEST=%ORIGEM%"
exit /b 0
