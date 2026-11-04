@echo off
chcp 65001 >nul
title Avisador de Treinamentos Mavaular - Remover
schtasks /Delete /F /TN "Avisador de Treinamentos Mavaular" >nul 2>&1
powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue ([Environment]::GetFolderPath('Startup')+'\Avisador de Treinamentos Mavaular.lnk')" >nul 2>&1
rmdir /S /Q "%LOCALAPPDATA%\TreinamentosMavaular" >nul 2>&1
rmdir /S /Q "%USERPROFILE%\Documents\Avisador de Treinamentos" >nul 2>&1
echo O Avisador de Treinamentos foi removido deste computador.
pause
