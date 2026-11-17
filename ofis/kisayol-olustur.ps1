<#
kisayol-olustur.ps1 - Masaüstüne "Creativity Office" kısayolunu (ve ofis.ico simgesini) kurar. Yönetici gerekmez.

  Kısayol: conhost.exe --headless powershell.exe ... ofis\ofis.ps1 -Ac
    * conhost --headless: konsol penceresi görünmez (Windows Script Host gerektirmez).
    * Panel sunucusu zaten çalışıyorsa yalnızca tarayıcıda paneli açar.

  .\ofis\kisayol-olustur.ps1            kısayolu kur / güncelle
  .\ofis\kisayol-olustur.ps1 -Kaldir    kısayolu kaldır
#>
param([switch]$Kaldir)
$ErrorActionPreference = 'Stop'
$ofis = $PSScriptRoot
$masaustu = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $masaustu 'Creativity Office.lnk'

if ($Kaldir) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "Kısayol kaldırıldı: $lnk" } else { Write-Host 'Kısayol zaten yok.' }
    return
}
. (Join-Path $ofis 'simge.ps1')
Simge-Uret $ofis -Ico
$ico = Join-Path $ofis 'ofis.ico'
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$betik = Join-Path $ofis 'ofis.ps1'
$kabuk = New-Object -ComObject WScript.Shell
try {
    $k = $kabuk.CreateShortcut($lnk)
    $k.TargetPath = $conhost
    $k.Arguments = ('--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -Ac' -f $ps, $betik)
    $k.WorkingDirectory = Split-Path -Parent $ofis
    $k.IconLocation = "$ico,0"
    $k.Description = 'Creativity Office canlı stüdyo panelini tarayıcıda açar (bu bilgisayar: 127.0.0.1:8766)'
    $k.WindowStyle = 7
    $k.Save()
} finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($kabuk) }
Write-Host "Kısayol hazır: $lnk"
