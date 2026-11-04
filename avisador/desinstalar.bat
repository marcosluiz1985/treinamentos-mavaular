@echo off
chcp 65001 >nul
title Avisador de Treinamentos Mavaular - Remover
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*aviso-treinamentos.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "AvisadorTreinamentosMavaular" /f >nul 2>&1
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Avisador de Treinamentos Mavaular.vbs" >nul 2>&1
schtasks /Delete /F /TN "Avisador de Treinamentos Mavaular" >nul 2>&1
powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue ([Environment]::GetFolderPath('Startup')+'\Avisador de Treinamentos Mavaular.lnk')" >nul 2>&1
rmdir /S /Q "%LOCALAPPDATA%\TreinamentosMavaular" >nul 2>&1
rmdir /S /Q "%USERPROFILE%\Documents\Avisador de Treinamentos" >nul 2>&1
echo O Avisador de Treinamentos foi removido deste computador.
pause
