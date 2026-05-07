@echo off
setlocal enabledelayedexpansion

:: Typola Post-Install Setup
:: Run silently after extraction, then launch Typola

set "INSTALL_DIR=%~dp0.."
pushd "%INSTALL_DIR%" 2>nul
set "INSTALL_DIR=%CD%"
popd

:: Clean old Typora registry entries
reg delete "HKCU\Software\Typora" /f >nul 2>&1

:: Create Start Menu shortcut
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Typola"
mkdir "%START_MENU%" 2>nul

set "VBS=%TEMP%\tpsetup.vbs"
(
echo Set WshShell = CreateObject^("WScript.Shell"^)
echo Set Shortcut = WshShell.CreateShortcut^("%START_MENU%\Typola.lnk"^)
echo Shortcut.TargetPath = "%INSTALL_DIR%\Typola.exe"
echo Shortcut.WorkingDirectory = "%INSTALL_DIR%"
echo Shortcut.Description = "Typola Markdown Editor"
echo Shortcut.IconLocation = "%INSTALL_DIR%\Typola.exe,0"
echo Shortcut.Save
) > "%VBS%"
cscript //nologo "%VBS%" >nul 2>&1
del "%VBS%" >nul 2>&1

:: Create Desktop shortcut
set "DESKTOP=%USERPROFILE%\Desktop"
if exist "%DESKTOP%" (
    set "VBS=%TEMP%\tpdesk.vbs"
    (
    echo Set WshShell = CreateObject^("WScript.Shell"^)
    echo Set Shortcut = WshShell.CreateShortcut^("%DESKTOP%\Typola.lnk"^)
    echo Shortcut.TargetPath = "%INSTALL_DIR%\Typola.exe"
    echo Shortcut.WorkingDirectory = "%INSTALL_DIR%"
    echo Shortcut.Description = "Typola Markdown Editor"
    echo Shortcut.IconLocation = "%INSTALL_DIR%\Typola.exe,0"
    echo Shortcut.Save
    ) > "%VBS%"
    cscript //nologo "%VBS%" >nul 2>&1
    del "%VBS%" >nul 2>&1
)

:: Launch Typola
start "" "%INSTALL_DIR%\Typola.exe"
