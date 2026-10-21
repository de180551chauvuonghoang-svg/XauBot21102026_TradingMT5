@echo off
chcp 65001 >nul
title MultiAssetEA v2 - Khoi Dong Tu Dong
color 0A

echo =====================================================================
echo           MULTIASSET EA v2 - HE THONG TRADING TU DONG MT5
echo                   (Python Brain + MT5 Execution)
echo =====================================================================
echo.

set PROJECT_DIR=%~dp0
set BRAIN_DIR=%PROJECT_DIR%brain
set MQL5_DIR=%PROJECT_DIR%mql5

if defined MT5_PATH (
    set MT5_EXE=%MT5_PATH%\terminal64.exe
    set METAEDITOR_EXE=%MT5_PATH%\metaeditor64.exe
) else (
    set MT5_EXE=C:\Program Files\MetaTrader 5\terminal64.exe
    set METAEDITOR_EXE=C:\Program Files\MetaTrader 5\metaeditor64.exe
    if not exist "!MT5_EXE!" (
        if exist "D:\metatradexau\terminal64.exe" (
            set MT5_EXE=D:\metatradexau\terminal64.exe
            set METAEDITOR_EXE=D:\metatradexau\metaeditor64.exe
        )
    )
)

set MT5_EXPERTS_DIR=%APPDATA%\MetaQuotes\Terminal\6E04D87B282C6D00B0407B7ADE5323EE\MQL5\Experts\MultiAssetEA

echo [1/4] Kiem tra moi truong Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [LOI] Khong tim thay Python! Vui long cai dat Python 3.10+.
    pause
    exit /b 1
)

echo [2/4] Dong bo va bien dich MQL5 EA...
if not exist "%MT5_EXPERTS_DIR%" mkdir "%MT5_EXPERTS_DIR%" >nul 2>&1
xcopy "%MQL5_DIR%\*" "%MT5_EXPERTS_DIR%\" /E /Y /Q >nul 2>&1

if exist "%METAEDITOR_EXE%" (
    "%METAEDITOR_EXE%" /compile:"%MT5_EXPERTS_DIR%\MultiAssetEA.mq5" /log:"%MT5_EXPERTS_DIR%\compile.log" >nul 2>&1
    echo       [OK] Da dong bo va bien dich MultiAssetEA.ex5!
)

echo [3/4] Kiem tra phan mem MetaTrader 5...
set MT5_RUNNING=0
for /f "tokens=1" %%i in ('tasklist /fi "imagename eq terminal64.exe" 2^>nul') do (
    if /i "%%i"=="terminal64.exe" set MT5_RUNNING=1
)

if "%MT5_RUNNING%"=="1" (
    echo       [OK] MetaTrader 5 dang chay.
) else (
    echo       Dang khoi dong MetaTrader 5...
    start "" "%MT5_EXE%"
    timeout /t 3 >nul
)

echo [4/4] Khoi dong Python Brain (4 Nguon Tin + Groq AI)...
echo =====================================================================
echo  He thong da san sang! Nhan [Ctrl + C] de dung bot.
echo =====================================================================
echo.

cd /d "%BRAIN_DIR%"
python main.py --mode demo

pause
