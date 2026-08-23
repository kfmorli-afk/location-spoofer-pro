@echo off
chcp 65001 >nul
title Location Spoofer Pro - GitHub Push
echo =======================================================
echo   Location Spoofer Pro - Upload zu GitHub
echo =======================================================
echo.
cd /d "%~dp0"
echo Bereite Dateien fuer https://github.com/kfmorli-afk/location-spoofer-pro.git vor...
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [!] Dieses Verzeichnis ist kein Git-Repository.
    goto :end
)

rem Erst alle lokalen Aenderungen committen. Die alte Version hat nur bereits
rem vorhandene Commits gepusht; dadurch blieben neue Workflow-Fixes lokal.
git add -A
git diff --cached --quiet
if errorlevel 1 (
    git commit -m "Update IPA build"
    if errorlevel 1 (
        echo [!] Commit fehlgeschlagen. Bitte pruefe die Git-Konfiguration.
        goto :end
    )
) else (
    echo [OK] Keine neuen Dateien zum Committen.
)

echo.
echo Lade Commit zu GitHub hoch...
git push -u origin main
echo.
if %ERRORLEVEL% equ 0 (
    echo =======================================================
    echo [OK] Erfolgreich hochgeladen!
    echo.
    echo Gehe jetzt zu:
    echo https://github.com/kfmorli-afk/location-spoofer-pro/actions
    echo.
    echo Der automatische IPA-Build startet dort in kuerze!
    echo =======================================================
) else (
    echo [!] Fehler beim Hochladen. Bitte pruefe deine GitHub-Anmeldedaten.
)
:end
echo.
pause
