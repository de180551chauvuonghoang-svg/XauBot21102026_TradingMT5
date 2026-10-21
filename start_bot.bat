@echo off
chcp 65001 >nul
title MultiAssetEA v2 - Khởi Động Tự Động
color 0A

echo =====================================================================
echo           MULTIASSET EA v2 - HỆ THỐNG TRADING TỰ ĐỘNG MT5
echo                   (Python Brain + MT5 Execution)
echo =====================================================================
echo.

set "PROJECT_DIR=%~dp0"
set "BRAIN_DIR=%PROJECT_DIR%brain"
set "MQL5_DIR=%PROJECT_DIR%mql5"

:: Tự động nhận diện đường dẫn cài đặt MT5
set "MT5_EXE=D:\metatradexau\terminal64.exe"
if not exist "%MT5_EXE%" set "MT5_EXE=C:\Program Files\MetaTrader 5\terminal64.exe"
if not exist "%MT5_EXE%" set "MT5_EXE=C:\Program Files (x86)\MetaTrader 5\terminal64.exe"

set "METAEDITOR_EXE=D:\metatradexau\metaeditor64.exe"
if not exist "%METAEDITOR_EXE%" set "METAEDITOR_EXE=C:\Program Files\MetaTrader 5\metaeditor64.exe"

:: Tự động tìm thư mục Terminal Experts trong AppData
set "MT5_EXPERTS_DIR=%APPDATA%\MetaQuotes\Terminal\6E04D87B282C6D00B0407B7ADE5323EE\MQL5\Experts\MultiAssetEA"
if not exist "%APPDATA%\MetaQuotes\Terminal\6E04D87B282C6D00B0407B7ADE5323EE" (
    for /d %%D in ("%APPDATA%\MetaQuotes\Terminal\*") do (
        if exist "%%D\MQL5\Experts" (
            set "MT5_EXPERTS_DIR=%%D\MQL5\Experts\MultiAssetEA"
            goto :found_terminal
        )
    )
)
:found_terminal

:: ---------------------------------------------------------
:: BƯỚC 1: KIỂM TRA MÔI TRƯỜNG PYTHON & .ENV
:: ---------------------------------------------------------
echo [1/4] Kiểm tra môi trường Python và cấu hình...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [LỖI] Không tìm thấy Python trên máy! Vui lòng cài đặt Python 3.10+.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%.env" (
    color 0E
    echo [CẢNH BÁO] Chưa tìm thấy file .env! Đang copy từ .env.example...
    copy "%PROJECT_DIR%.env.example" "%PROJECT_DIR%.env" >nul
    echo Vui lòng mở file .env và điền các API Key trước khi chạy.
)

:: ---------------------------------------------------------
:: BƯỚC 2: ĐỒNG BỘ VÀ COMPILE MQL5 EXPERT ADVISOR
:: ---------------------------------------------------------
echo [2/4] Tự động đồng bộ và Compile EA sang MT5 Experts...
if not exist "%MT5_EXPERTS_DIR%" (
    mkdir "%MT5_EXPERTS_DIR%" >nul 2>&1
)

xcopy "%MQL5_DIR%\*" "%MT5_EXPERTS_DIR%\" /E /Y /Q >nul 2>&1

if exist "%METAEDITOR_EXE%" (
    echo       Đang biên dịch MultiAssetEA.mq5 qua MetaEditor...
    "%METAEDITOR_EXE%" /compile:"%MT5_EXPERTS_DIR%\MultiAssetEA.mq5" /log:"%MT5_EXPERTS_DIR%\compile.log" >nul 2>&1
    if exist "%MT5_EXPERTS_DIR%\MultiAssetEA.ex5" (
        echo       [OK] Đã biên dịch MultiAssetEA.ex5 thành công!
    ) else (
        echo       [CẢNH BÁO] Kiểm tra log compile tại: %MT5_EXPERTS_DIR%\compile.log
    )
) else (
    echo       [BỎ QUA] Không tìm thấy MetaEditor tại: %METAEDITOR_EXE%
)

:: ---------------------------------------------------------
:: BƯỚC 3: KIỂM TRA VÀ KHỞI ĐỘNG METATRADER 5
:: ---------------------------------------------------------
echo [3/4] Kiểm tra phần mềm MetaTrader 5...
tasklist /FI "IMAGENAME eq terminal64.exe" 2>NUL | find /I /N "terminal64.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo       [OK] MetaTrader 5 đã đang chạy.
) else (
    if exist "%MT5_EXE%" (
        echo       Đang khởi động MetaTrader 5...
        start "" "%MT5_EXE%"
        timeout /t 3 >nul
        echo       [OK] Đã mở MetaTrader 5.
    ) else (
        echo       [CẢNH BÁO] Không tìm thấy MT5 tại %MT5_EXE%. Vui lòng mở MT5 thủ công.
    )
)

:: ---------------------------------------------------------
:: BƯỚC 4: KHỞI ĐỘNG PYTHON BRAIN
:: ---------------------------------------------------------
echo [4/4] Khởi động Python Brain (4 Nguồn Tin Tức + Groq AI)...
echo.
echo =====================================================================
echo  Hệ thống đã sẵn sàng! 
echo  Python Brain đang chạy và liên tục phân tích tin tức từ 4 nguồn.
echo  Để dừng hệ thống, nhấn tổ hợp phím [Ctrl + C] tại cửa sổ này.
echo =====================================================================
echo.

cd /d "%BRAIN_DIR%"
python main.py --mode demo

pause
