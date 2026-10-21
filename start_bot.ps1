# Script khoi dong MultiAssetEA tren PowerShell
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "          MULTIASSET EA v2 - HE THONG TRADING TU DONG MT5           " -ForegroundColor Green
Write-Host "                  (Python Brain + MT5 Execution)                     " -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$brainDir = Join-Path $projectDir "brain"
$mql5Dir = Join-Path $projectDir "mql5"
$mt5PathEnv = $env:MT5_PATH
if ($mt5PathEnv -and (Test-Path "$mt5PathEnv\terminal64.exe")) {
    $mt5Exe = "$mt5PathEnv\terminal64.exe"
    $metaEditorExe = "$mt5PathEnv\metaeditor64.exe"
} else {
    $candidates = @("C:\Program Files\MetaTrader 5", "D:\metatradexau")
    $found = $false
    foreach ($cand in $candidates) {
        if (Test-Path "$cand\terminal64.exe") {
            $mt5Exe = "$cand\terminal64.exe"
            $metaEditorExe = "$cand\metaeditor64.exe"
            $found = $true
            break
        }
    }
    if (-not $found) {
        $mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe"
        $metaEditorExe = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
    }
}
$expertsDir = "$env:APPDATA\MetaQuotes\Terminal\6E04D87B282C6D00B0407B7ADE5323EE\MQL5\Experts\MultiAssetEA"

Write-Host "`n[1/4] Kiem tra moi truong Python..." -ForegroundColor Cyan
python --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "[LOI] Khong tim thay Python! Vui long cai dat Python 3.10+." -ForegroundColor Red
    pause
    exit 1
}

Write-Host "`n[2/4] Dong bo va bien dich MQL5 EA..." -ForegroundColor Cyan
if (-not (Test-Path $expertsDir)) { New-Item -ItemType Directory -Path $expertsDir -Force | Out-Null }
Copy-Item -Path "$mql5Dir\*" -Destination $expertsDir -Recurse -Force | Out-Null

if (Test-Path $metaEditorExe) {
    Start-Process -FilePath $metaEditorExe -ArgumentList "/compile:`"$expertsDir\MultiAssetEA.mq5`" /log:`"$expertsDir\compile.log`"" -Wait
    Write-Host "      [OK] Da bien dich MultiAssetEA.ex5 thanh cong!" -ForegroundColor Green
}

Write-Host "`n[3/4] Kiem tra MetaTrader 5..." -ForegroundColor Cyan
$mt5Proc = Get-Process -Name "terminal64" -ErrorAction SilentlyContinue
if ($mt5Proc) {
    Write-Host "      [OK] MetaTrader 5 dang chay." -ForegroundColor Green
} else {
    Write-Host "      Dang khoi dong MetaTrader 5..." -ForegroundColor Yellow
    Start-Process -FilePath $mt5Exe
    Start-Sleep -Seconds 3
}

Write-Host "`n[4/4] Khoi dong Python Brain..." -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " He thong da san sang! Nhan [Ctrl + C] de dung bot." -ForegroundColor Green
Write-Host "=====================================================================`n" -ForegroundColor Green

Set-Location $brainDir
python main.py --mode demo
