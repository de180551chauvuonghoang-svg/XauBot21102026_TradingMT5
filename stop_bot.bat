@echo off
chcp 65001 >nul
title Dung He Thong MultiAssetEA
echo Dang dung Python Brain...
taskkill /f /im python.exe /fi "WINDOWTITLE eq MultiAssetEA*" >nul 2>&1
taskkill /f /fi "IMAGENAME eq python.exe" >nul 2>&1
echo [OK] Da dung Brain thanh cong.
pause
