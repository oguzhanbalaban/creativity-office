<#
Panelden bir ajana yazılan mesajı yanıtlar (ofis.ps1 başlatır; pencere açmaz).
Ajan salt okunur çalışır: dosya değiştirmez, iş göndermez. Yeni konu önerisi ```konu {json}``` bloğuyla gelir;
panel bunu kullanıcıya düğme olarak gösterir, kullanıcı onaylamadan hiçbir şey eklenmez.
#>
param([Parameter(Mandatory)][ValidatePattern('^[a-z][a-z-]{1,29}$')][string]$Rol)
$ErrorActionPreference = 'Stop'
# Etkileşimli oturumdan devralınan değişkenler arka plandaki claude.exe girişini bozar.
foreach ($ad in @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } | ForEach-Object { $_.Name })) { Remove-Item -LiteralPath "env:$ad" -ErrorAction SilentlyContinue }
$kokYol = Split-Path -Parent $PSScriptRoot
. (Join-Path $kokYol 'ortak.ps1')
# Sohbet ayrı süreçtir: ajan döngüsünün kalp dosyasını ezmesin.
function Kalp([string]$Durum) { }
Ayarlari-Yukle
$kadro = Json-Oku (Join-Path $Kok 'kadro.json')
$uye = @($kadro.uyeler | Where-Object { $_.anahtar -eq $Rol } | Select-Object -First 1)
if (-not $uye.Count) { throw "Bilinmeyen rol: $Rol" }
$uye = $uye[0]
$dizin = Join-Path $YolDurum 'sohbet'
if (-not (Test-Path -LiteralPath $dizin)) { New-Item -ItemType Directory -Force $dizin | Out-Null }
$dosya = Join-Path $dizin "$Rol.jsonl"
$pidDosya = Join-Path $dizin "$Rol.pid"

function Mesajlar {
    $liste = @()
    foreach ($s in ((Metin-Oku $dosya) -split "`n")) { if ($s.Trim()) { try { $liste += ($s | ConvertFrom-Json) } catch {} } }
    return ,$liste
}
function Ekle([string]$Kim, [string]$Metin, [string]$Arac = '') {
    $satir = ConvertTo-Json -Compress -InputObject ([ordered]@{ zaman = (Simdi); kim = $Kim; metin = $Metin; arac = $Arac })
    [IO.File]::AppendAllText($dosya, $satir + "`n", $Utf8)
}
function Ofis-Ozeti {
    $b = New-Object Text.StringBuilder
    $acik = -not (Test-Path -LiteralPath (Join-Path $Kok 'DURDUR'))
    [void]$b.AppendLine("Ofis: $(if ($acik) { 'açık' } else { 'kapalı' }). Revizyon sınırı: $($Ayar.revizyon_siniri). AI Ofis köprüsü: $(if (([string]$Ayar.ana_ofis_yolu).Trim()) { 'bağlı' } else { 'yok (yerel teslim)' }).")
    $gorevler = @(Gorevleri-Listele | Sort-Object id -Descending | Select-Object -First 12)
    if (-not $gorevler.Count) { [void]$b.AppendLine('Henüz konu yok.') }
    foreach ($g in $gorevler) {
        $puan = ''; if ($g.PSObject.Properties['puan'] -and $g.puan) { $puan = ", puan $($g.puan)/10" }
        [void]$b.AppendLine(("- [{0}] {1} (alan: {2}, revizyon {3}{4}) klasör: gorevler/{5}" -f $g.asama, $g.baslik, $g.alan, $g.revizyon, $puan, $g.id))
    }
    return $b.ToString()
}

$mutex = [Threading.Mutex]::new($false, "Local\YaraticiSohbet-$Rol")
$sahip = $false
try {
    try { $sahip = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sahip = $true }
    if (-not $sahip) { return }
    $p = Get-Process -Id $PID
    [IO.File]::WriteAllText($pidDosya, (ConvertTo-Json -InputObject ([ordered]@{ pid = $PID; baslangic = $p.StartTime.ToString('o') })), $Utf8)
    for ($tur = 0; $tur -lt 4; $tur++) {
        $m = Mesajlar
        if (-not $m.Count -or $m[-1].kim -ne 'sen') { break }
        # Yanıtlanmamış ardışık mesajlar tek seferde yanıtlanır.
        $yeni = @(); $i = $m.Count - 1
        while ($i -ge 0 -and $m[$i].kim -eq 'sen') { $yeni = @($m[$i].metin) + $yeni; $i-- }
        $gecmis = @($m | Select-Object -First ($i + 1) | Select-Object -Last 12 | ForEach-Object { '{0}: {1}' -f $(if ($_.kim -eq 'sen') { 'Kullanıcı' } elseif ($_.kim -eq 'ajan') { $uye.rol } else { 'Sistem' }), (Kisalt ([string]$_.metin) 1200) })
        $istem = Sablon-Doldur 'sohbet.md' @{
            ROL = [string]$uye.rol; GOREV = [string]$uye.gorev; DURUM = (Ofis-Ozeti)
            GECMIS = $(if ($gecmis.Count) { $gecmis -join "`n" } else { '(ilk mesaj)' }); MESAJ = ($yeni -join "`n")
        }
        $script:AktifGorev = "sohbet-$Rol"
        $r = Ajan-Cagir -Rol $Rol -Istem $istem -Klasor $Kok -KayitKlasoru (Join-Path $dizin "kayit\$Rol") -Etiket "sohbet-$Rol"
        if ($r.basarili -and ([string]$r.metin).Trim()) { Ekle 'ajan' ([string]$r.metin).Trim() ("{0}/{1}" -f $r.arac, $r.model) }
        else { Ekle 'sistem' ("Yanıt alınamadı: " + (Kisalt ([string]$r.hata) 400)); break }
    }
} catch {
    try { Ekle 'sistem' ("Sohbet hatası: " + (Kisalt $_.Exception.Message 300)) } catch {}
} finally {
    if ($sahip) { try { Remove-Item -LiteralPath $pidDosya -Force -ErrorAction SilentlyContinue } catch {}; $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
