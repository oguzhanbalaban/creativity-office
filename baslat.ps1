param([switch]$Konsol, [ValidateRange(0,2147483647)][int]$AdimSiniri = 0, [switch]$BosBitir)
$ErrorActionPreference = 'Stop'
$script:Konsol = [bool]$Konsol
. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'dongu.ps1')
Ayarlari-Yukle
$mutex = New-Object Threading.Mutex($false, 'Local\YaraticiOfisDongusu')
$sahip = $false
try {
    try { $sahip = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sahip = $true }
    if (-not $sahip) {
        $kalp = Json-Oku (Join-Path $YolDurum 'kalp.json')
        if ($kalp -and ((Get-Date) - [datetime]$kalp.zaman).TotalMinutes -ge [double]$Ayar.dongu.bekci_dk) {
            # PID yeniden kullanılmış olabilir; aynı betik ve başlangıç zamanı doğrulanmadan öldürme.
            $aday = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$kalp.pid)" -ErrorAction SilentlyContinue
            $betik = Join-Path $PSScriptRoot 'baslat.ps1'
            if ($aday -and $kalp.baslangic -and $aday.CommandLine -and
                $aday.CommandLine.IndexOf($betik, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                [Math]::Abs((([datetime]$aday.CreationDate) - [datetime]$kalp.baslangic).TotalSeconds) -lt 2 -and [int]$kalp.pid -ne $PID) {
                Gunluk 'Bekçi: doğrulanan donmuş yaratıcı ofis süreci sonlandırılıyor.' 'UYARI'
                & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $kalp.pid 2>$null | Out-Null
                try { $sahip = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $sahip = $true }
            } else { Gunluk 'Bekçi: eski kalp var, süreç kimliği doğrulanamadı; başka sürece dokunulmadı.' 'UYARI' }
        }
        if (-not $sahip) { return }
    }
    $script:SurecBaslangici = (Get-Process -Id $PID).StartTime.ToString('o')
    Kalp 'başladı'
    $sonuc = Yaratici-Dongusu -AdimSiniri $AdimSiniri -BosBitir:$BosBitir
    Gunluk "Yaratıcı ofis sona erdi: $sonuc"
} finally {
    if ($sahip) { Kalp 'durdu'; $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
