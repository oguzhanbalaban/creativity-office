<#
telefon-kur.ps1 - Creativity Office panelini telefondan (ev dışından da) açmak için Tailscale ile uzaktan erişimi kurar.

Önce (bir kez):
  1. Bilgisayara ve telefona Tailscale'i kur, ikisinde de AYNI hesapla giriş yap.
  2. Tailscale yönetim sayfasında MagicDNS ve "HTTPS Certificates" açık olsun: https://login.tailscale.com/admin/dns
Sonra:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ofis\telefon-kur.ps1

Ne yapar:
  - ofis\uzak.json'a bilgisayarın Tailscale adını ve senin Tailscale hesabını yazar: panel uzaktan yalnızca bu hesabı kabul eder.
    AI Ofis (AI Ekip) de telefona açıksa onun adresini de yazar; paneldeki "AI Ofis" düğmesi telefondan oraya gider.
  - Panel sunucusunu yeniden başlatır ve "tailscale serve" ile yalnızca senin Tailscale ağına açar: https://<bilgisayar>.<ağ>.ts.net:8443/
    (443 portu AI Ofis'e ayrılmış olabilir; Creativity Office ayrı portta durur, ikisi birbirini bozmaz.)
    Panel yine yalnızca 127.0.0.1'i dinler; güvenlik duvarına dokunulmaz; internete açılmaz (Funnel kullanılmaz).
  - Panel sunucusu hep açık kalsın diye "\Creativity-Office\Panel" zamanlanmış görevini kurar (oturum açılınca, 10 dakikada bir).
    Ofisin kendisi (ajan döngüsü) yine panelden "Ofisi aç / kapat" ile yönetilir.

  .\ofis\telefon-kur.ps1 -Kaldir   uzaktan erişimi kapatır (yalnızca 8443 serve kaydı, uzak.json ve zamanlanmış görev silinir)
#>
param([switch]$Kaldir, [ValidateRange(1,65535)][int]$UzakPort = 8443)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Ofis = $PSScriptRoot
$Utf8 = New-Object Text.UTF8Encoding $false
$UzakDosyasi = Join-Path $Ofis 'uzak.json'
$GorevAdi = 'Panel'; $GorevYolu = '\Creativity-Office\'

function Tailscale-Exe {
    foreach ($a in @((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'))) { if ($a -and (Test-Path -LiteralPath $a)) { return $a } }
    $c = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
function Sunucu-Bilgisi { try { return (Get-Content -LiteralPath (Join-Path $Ofis 'sunucu.json') -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }
function Panel-Yeniden-Baslat {
    $s = Sunucu-Bilgisi
    if ($s -and $s.pid) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$s.pid)" -ErrorAction SilentlyContinue
        # Yalnızca bu klasördeki panel sürecini durdur (PID yeniden kullanılmış olabilir).
        if ($p -and $p.CommandLine -and $p.CommandLine.IndexOf((Join-Path $Ofis 'ofis.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { Stop-Process -Id $p.ProcessId -Force; Start-Sleep -Seconds 2 }
    }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -WindowStyle Hidden -WorkingDirectory (Split-Path -Parent $Ofis) `
        -ArgumentList ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ofis 'ofis.ps1'))
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        $s = Sunucu-Bilgisi
        if ($s -and $s.pid -and (Get-Process -Id ([int]$s.pid) -ErrorAction SilentlyContinue)) { return [int]$s.port }
    }
    throw 'Panel sunucusu başlatılamadı; ofis\ofis.log dosyasına bak.'
}
function Gorev-Kur {
    $kullanici = "$env:USERDOMAIN\$env:USERNAME"
    $eylem = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') `
        -Argument ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ofis 'ofis.ps1')) -WorkingDirectory (Split-Path -Parent $Ofis)
    $tetik = New-ScheduledTaskTrigger -AtLogOn -User $kullanici
    $tetik.Delay = 'PT1M'
    $desen = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)).Repetition
    $desen.Duration = ''
    $tetik.Repetition = $desen
    $kimlik = New-ScheduledTaskPrincipal -UserId $kullanici -LogonType Interactive -RunLevel Limited
    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Compatibility Win8
    $ayar.Hidden = $true
    if (Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Confirm:$false }
    Register-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Action $eylem -Trigger $tetik -Principal $kimlik -Settings $ayar `
        -Description 'Creativity Office paneli: telefondan erişim için panel sunucusunu açık tutar (ikinci kopya kendiliğinden çıkar). Ofis açıksa ajan döngüsünü de ayağa kaldırır.' | Out-Null
    Write-Host "Zamanlanmış görev kuruldu: $GorevYolu$GorevAdi (oturum açılınca başlar, 10 dakikada bir kontrol eder)."
}

$ts = Tailscale-Exe
if ($Kaldir) {
    if ($ts) { & $ts serve --https=$UzakPort off 2>&1 | Out-Host }
    if (Test-Path -LiteralPath $UzakDosyasi) { Remove-Item -LiteralPath $UzakDosyasi -Force }
    if (Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Confirm:$false }
    [void](Panel-Yeniden-Baslat)
    Write-Host 'Uzaktan erişim kapatıldı. Panel yine yalnızca bu bilgisayardan açılır.'
    return
}
if (-not $ts) { Write-Host 'Tailscale bulunamadı. Önce https://tailscale.com/download/windows adresinden kurup hesabınla giriş yap.'; exit 1 }
$st = (& $ts status --json) -join "`n" | ConvertFrom-Json
if ($st.BackendState -ne 'Running') { Write-Host "Tailscale bağlı değil (durum: $($st.BackendState)). Görev çubuğundaki Tailscale simgesinden bağlan, sonra yeniden dene."; exit 1 }
$hostAdi = ([string]$st.Self.DNSName).TrimEnd('.').ToLowerInvariant()
$kullanici = ''
$u = $st.User.PSObject.Properties[[string]$st.Self.UserID]
if ($u) { $kullanici = ([string]$u.Value.LoginName).ToLowerInvariant() }
if (-not $hostAdi) { Write-Host 'Bilgisayarın Tailscale adı alınamadı. MagicDNS açık mı? https://login.tailscale.com/admin/dns'; exit 1 }
if (-not @($st.CertDomains).Count) { Write-Host 'Tailscale ağında HTTPS sertifikaları kapalı. https://login.tailscale.com/admin/dns sayfasında "HTTPS Certificates" > Enable de.'; exit 1 }
if (-not $kullanici) { Write-Host 'Tailscale hesap adı alınamadı; yeniden giriş yapıp dene.'; exit 1 }

# AI Ofis telefona açık mı? (443'te bir serve kaydı varsa onun adresi "AI Ofis" düğmesinde kullanılır)
$anaPanel = ''
try {
    $serve = (& $ts serve status --json) -join "`n" | ConvertFrom-Json
    if ($serve.Web -and $serve.Web.PSObject.Properties["$($hostAdi):443"]) { $anaPanel = "https://$hostAdi/" }
} catch {}
[IO.File]::WriteAllText($UzakDosyasi, (ConvertTo-Json -InputObject ([ordered]@{ hostlar = @($hostAdi); kullanicilar = @($kullanici); ana_panel = $anaPanel; port = $UzakPort; kurulum = (Get-Date).ToString('o') })), $Utf8)
Write-Host "Uzak erişim ayarı yazıldı: $hostAdi (yalnızca $kullanici)"
$port = Panel-Yeniden-Baslat
Write-Host "Panel sunucusu yeniden başladı (127.0.0.1:$port)."
$cikti = & $ts serve --bg --https=$UzakPort "http://127.0.0.1:$port" 2>&1
$kod = $LASTEXITCODE
$cikti | Out-Host
if ($kod -ne 0) { Write-Host 'tailscale serve başarısız oldu. Yukarıdaki mesajda bir bağlantı varsa açıp onayla, sonra betiği yeniden çalıştır.'; exit 1 }
Gorev-Kur
Write-Host ''
Write-Host '================ HAZIR ================'
Write-Host "Telefonda Tailscale açıkken tarayıcıda şu adresi aç:  https://$($hostAdi):$UzakPort/"
Write-Host 'Sonra tarayıcının menüsünden "Ana ekrana ekle" de; Creativity Office uygulama gibi açılır.'
if ($anaPanel) { Write-Host "AI Ofis: $anaPanel" }
Write-Host 'Bu adresler yalnızca senin Tailscale cihazlarından açılır; internete açık değildir.'
