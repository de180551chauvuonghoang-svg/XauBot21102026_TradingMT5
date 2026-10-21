@echo off
chcp 65001 >nul
title MultiAssetEA v2 - Dừng Bot
color 0C

echo =====================================================================
echo                MULTIASSET EA v2 - DỪNG HỆ THỐNG
echo =====================================================================
echo.

echo Đang dừng các tiến trình Python Brain...
taskkill /F /FI "WINDOWTITLE eq MultiAssetEA v2*" >nul 2>&1
taskkill /F /IM python.exe /FI "MODULES eq MetaTrader5*" >nul 2>&1

echo [OK] Đã dừng Python Brain an toàn.
echo.
echo Lưu ý: MetaTrader 5 vẫn giữ nguyên để bảo vệ các lệnh đang mở (nếu có).
pause
