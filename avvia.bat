@echo off
REM Launcher per Subst-Manager.ps1 (richiede admin)
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Subst-Manager.ps1"
) else (
    echo PowerShell 7 non trovato!
    pause
    exit /b 1
)
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Errore durante l'esecuzione.
    pause
)
endlocal
