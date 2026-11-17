<#
Creativity Office paneli: canlı piksel stüdyo + yönetim API'si.

  powershell -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Ac      # paneli başlat ve tarayıcıda aç
  powershell -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Durdur  # paneli durdur

Güvenlik:
  * HTTP.sys/URL ACL veya yönetici izni gerekmez: TcpListener yalnızca IPv4 loopback (127.0.0.1) dinler.
  * Host başlığı denetlenir (DNS rebinding), Origin/Sec-Fetch-Site siteler arası istekleri reddeder.
  * Oturum anahtarı her açılışta üretilir, yalnızca bellekte ve sunulan HTML'dedir; tüm /api isteklerinde aranır.
  * Telefondan erişim isteğe bağlıdır: ofis\uzak.json (telefon-kur.ps1 yazar). Tailscale serve isteği yine
    127.0.0.1'e iletir; uzak istek yalnızca uzak.json'daki Tailscale hesabıyla (Tailscale-User-Login) kabul edilir.
Ofis:
  * "Ofisi aç" ajan döngüsünü (baslat.ps1) başlatır, "Ofisi kapat" DURDUR dosyası bırakır (çalışan adım biter, ekip çıkar).
  * Ofis açıkken döngü kapanırsa panel onu yeniden başlatır (bekçi). Niyet durum\ofis.json'da tutulur.
#>
param(
    [ValidateRange(1024,65000)][int]$Port = 8766,
    [switch]$Ac,
    [switch]$Konsol,
    [switch]$Durdur,
    [ValidateRange(0,1440)][int]$BosKapanDk = 60
)
$ErrorActionPreference = 'Stop'
$script:PanelKok = $PSScriptRoot
$script:VeriKok = Split-Path -Parent $PSScriptRoot
$script:Kodlama = New-Object Text.UTF8Encoding $false
$script:SunucuYolu = Join-Path $PanelKok 'sunucu.json'
$script:Kapat = $false
$script:SonBaslatma = [datetime]::MinValue
$script:IstekUzak = $false
$script:Asamalar = @('yeni','fikir','elestiri','poc_plan','maliyet','karar','teslim','bekleme','puanlama','tamam')
$script:AsamaRol = @{ fikir='fikirci'; elestiri='elestirmen'; poc_plan='planlamaci'; maliyet='maliyet'; karar='karar-verici'; teslim='karar-verici'; puanlama='puanlayici' }
$script:RolBilgi = [ordered]@{
    'fikirci'      = @{ ad='Fikir Üretici';    renk='#f59e0b' }
    'elestirmen'   = @{ ad='Eleştirmen';       renk='#ef4444' }
    'planlamaci'   = @{ ad='POC Planlayıcı';   renk='#3b82f6' }
    'maliyet'      = @{ ad='Maliyet Analisti'; renk='#10b981' }
    'karar-verici' = @{ ad='Karar Verici';     renk='#8b5cf6' }
    'puanlayici'   = @{ ad='Puanlayıcı';       renk='#ec4899' }
}
$script:EnFazlaSohbet = 3

# ---------------------------------------------------------------- dosya yardımcıları
function Kayit([string]$Mesaj) {
    $satir = '{0} {1}' -f (Get-Date).ToString('s'), $Mesaj
    if ($Konsol) { Write-Host $satir }
    $yol = Join-Path $PanelKok 'ofis.log'
    try {
        if ((Test-Path -LiteralPath $yol) -and (Get-Item -LiteralPath $yol).Length -gt 1MB) { [IO.File]::WriteAllText($yol, '', $Kodlama) }
        [IO.File]::AppendAllText($yol, "$satir`r`n", $Kodlama)
    } catch {}
}
function Metin([string]$Yol, [int]$Sinir = 262144) {
    # Junction/symlink üzerinden ofis kökü dışındaki dosyalar sunulmaz.
    $aday = $Yol
    while ($aday -and $aday.Length -ge $VeriKok.Length) {
        if ((Test-Path -LiteralPath $aday) -and ((Get-Item -LiteralPath $aday -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'HTTP:400:Bağlantılı dosya veya klasör kullanılamaz.' }
        if ($aday -eq $VeriKok) { break }
        $aday = Split-Path -Parent $aday
    }
    return (DisMetin $Yol $Sinir)
}
# Paylaşımlı okuma (yazıcı dosyayı açık tutarken de okunur); boyut sınırlı.
function DisMetin([string]$Yol, [int]$Sinir = 262144) {
    if (-not $Yol -or -not [IO.File]::Exists($Yol)) { return '' }
    $akis = [IO.FileStream]::new($Yol, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $okuyucu = [IO.StreamReader]::new($akis, $Kodlama, $true)
        try {
            $tampon = New-Object char[] ($Sinir + 1)
            $n = $okuyucu.ReadBlock($tampon, 0, $tampon.Length)
            $sonuc = [string]::new($tampon, 0, [Math]::Min($n, $Sinir))
            if ($n -gt $Sinir) { $sonuc += "`n[Belge kısaltıldı]" }
            return $sonuc
        } finally { $okuyucu.Dispose() }
    } finally { $akis.Dispose() }
}
function Json([string]$Yol) {
    foreach ($aday in @($Yol, "$Yol.bak")) {
        try { $m = Metin $aday; if ($m.Trim()) { return ($m | ConvertFrom-Json) } } catch {}
    }
    return $null
}
function DisJson([string]$Yol) {
    foreach ($aday in @($Yol, "$Yol.bak")) {
        try { $m = DisMetin $aday 1048576; if ($m.Trim()) { return ($m | ConvertFrom-Json) } } catch {}
    }
    return $null
}
function JsonYaz($Nesne, [string]$Yol) {
    $tmp = "$Yol.tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Nesne -Depth 8), $Kodlama)
    if ([IO.File]::Exists($Yol)) { [IO.File]::Delete($Yol) }
    [IO.File]::Move($tmp, $Yol)
}
function YerelYol([string]$Ad) {
    $y = Join-Path $VeriKok "$Ad.yerel.json"
    if ((Test-Path -LiteralPath $y) -or (Test-Path -LiteralPath "$y.bak")) { return $y }
    return (Join-Path $VeriKok "$Ad.json")
}
function Ayarlar { $a = Json (YerelYol 'ayarlar'); if (-not $a) { $a = [pscustomobject]@{} }; return $a }
function Klasor([string]$Goreli) { $d = Join-Path $VeriKok $Goreli; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }; return $d }
function SurecCanli($Bilgi) {
    if (-not $Bilgi -or -not $Bilgi.pid) { return $false }
    try {
        $p = Get-Process -Id ([int]$Bilgi.pid) -ErrorAction Stop
        if (-not $Bilgi.baslangic) { return $true }
        return ([Math]::Abs(($p.StartTime - [datetime]$Bilgi.baslangic).TotalSeconds) -lt 2)
    } catch { return $false }
}

# ---------------------------------------------------------------- görevler
function GorevYolu([string]$Id) {
    if ($Id -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,119}$') { throw 'HTTP:400:Geçersiz görev kimliği.' }
    return (Join-Path (Join-Path $VeriKok 'gorevler') $Id)
}
function Karar-Satiri([string]$Yol) {
    $m = DisMetin $Yol 8192
    $k = [regex]::Match($m, '(?m)^KARAR:\s*(ONAYLA|REVIZE|REDDET)\s*$')
    if ($k.Success) { return $k.Groups[1].Value }
    return ''
}
function Ana-Kok($A, $G) {
    $yol = ''
    if ($G -and $G.PSObject.Properties['ana_ofis'] -and $G.ana_ofis) { $yol = [string]$G.ana_ofis }
    elseif ($A.PSObject.Properties['ana_ofis_yolu']) { $yol = [string]$A.ana_ofis_yolu }
    if (-not $yol.Trim()) { return '' }
    if (-not [IO.Path]::IsPathRooted($yol)) { $yol = Join-Path $VeriKok $yol }
    return $yol
}
function Gorev-Ozet([string]$Id, $G, $A, [int]$No) {
    $gk = GorevYolu $Id
    $alan = { param($ad) if ($G.PSObject.Properties[$ad]) { return $G.$ad } else { return $null } }
    $anaAsama = & $alan 'ana_asama'
    $anaId = [string](& $alan 'ana_gorev_id')
    if ($G.asama -in @('bekleme','puanlama') -and $anaId -and $anaId -match '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,119}$') {
        $kok = Ana-Kok $A $G
        if ($kok) { $ag = DisJson (Join-Path (Join-Path (Join-Path $kok 'gorevler') $anaId) 'durum.json'); if ($ag -and $ag.asama) { $anaAsama = [string]$ag.asama } }
    }
    $gecmis = @($G.gecmis)
    return [ordered]@{
        id = $Id; no = $No; baslik = $G.baslik; alan = $G.alan; proje = $G.proje; asama = $G.asama
        takildi_asama = (& $alan 'takildi_asama'); revizyon = $G.revizyon; puan = (& $alan 'puan')
        karar = (Karar-Satiri (Join-Path $gk 'karar.md')); son_hata = $G.son_hata; deneme = $G.deneme
        sonraki_deneme = $G.sonraki_deneme; olusturma = $G.olusturma; guncelleme = (& $alan 'guncelleme')
        ana_gorev_id = $anaId; ana_asama = $anaAsama; teslim_turu = (& $alan 'teslim_turu')
        gecmis = @($gecmis | Select-Object -Last 12)
    }
}
function Gorev([string]$Id, [int]$No = 0) {
    $yol = GorevYolu $Id
    $g = Json (Join-Path $yol 'durum.json')
    if (-not $g) { throw 'HTTP:404:Görev bulunamadı veya durum dosyası okunamıyor.' }
    # JSON içindeki kimliğe değil doğrulanmış klasör adına güvenilir.
    return (Gorev-Ozet $Id $g (Ayarlar) $No)
}
function Gorev-Listesi($A) {
    $dizin = Join-Path $VeriKok 'gorevler'
    $klasorler = @(Get-ChildItem -LiteralPath $dizin -Directory -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object Name)
    $liste = New-Object Collections.Generic.List[object]
    $no = 0
    foreach ($d in $klasorler) {
        $no++
        if ($d.Name -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,119}$') { continue }
        $g = Json (Join-Path $d.FullName 'durum.json')
        if (-not $g) { Kayit 'Okunamayan bir görev atlandı.'; continue }
        try { $liste.Add((Gorev-Ozet $d.Name $g $A $no)) } catch { Kayit 'Okunamayan bir görev atlandı.' }
    }
    $liste.Reverse()
    return ,$liste.ToArray()
}

# ---------------------------------------------------------------- döngü ve ofis durumu
function Dongu-Durumu {
    $kalp = Json (Join-Path $VeriKok 'durum/kalp.json')
    $s = [ordered]@{ canli = $false; donmus = $false; saglik = 'durdu'; rol = ''; gorev = ''; adim = ''; arac = ''; kalp = $kalp }
    if (-not $kalp) { return $s }
    if ($kalp.durum -eq 'durdu' -or -not (SurecCanli $kalp)) { return $s }
    $yas = 1e9
    try { $yas = ((Get-Date) - [datetime]$kalp.zaman).TotalSeconds } catch {}
    if ($yas -lt -5 -or $yas -ge 90) { $s.donmus = $true; return $s }
    $s.canli = $true; $s.saglik = 'bosta'
    $d = [string]$kalp.durum
    # Bekleme kalbi önceki görev/adım bilgisini taşıyabilir; yalnızca adım ve ajan çağrısı etkin sayılır.
    if ($d -eq 'adım' -or $d -eq 'ajan' -or $d -match ' çalışıyor$') {
        $adim = [string]$kalp.adim; $rol = ''; $arac = ''
        if ($adim -match '^([a-z-]+) \(([^)]*)\)$') { $rol = $Matches[1]; $arac = $Matches[2] }
        elseif ($AsamaRol.ContainsKey($adim)) { $rol = $AsamaRol[$adim] }
        if ($rol -eq 'teslim') { $rol = 'karar-verici' }
        if ($RolBilgi.Contains($rol)) { $s.saglik = 'calisiyor'; $s.rol = $rol; $s.gorev = [string]$kalp.gorev; $s.adim = $adim; $s.arac = $arac }
    }
    return $s
}
function Ofis-Niyeti { $o = Json (Join-Path $VeriKok 'durum/ofis.json'); return [bool]($o -and $o.acik) }
function Niyet-Yaz([bool]$Acik) { $null = Klasor 'durum'; JsonYaz ([ordered]@{ acik = $Acik; zaman = (Get-Date).ToString('o') }) (Join-Path $VeriKok 'durum/ofis.json') }
function Mesai($A) {
    try {
        $p = ([string]$A.dongu.calisma_saatleri).Split('-')
        $bas = [TimeSpan]::Parse($p[0]).TotalMinutes; $son = 1440
        if ($p[1] -ne '24:00') { $son = [TimeSpan]::Parse($p[1]).TotalMinutes }
        $simdi = (Get-Date).TimeOfDay.TotalMinutes
        if ($bas -le $son) { return ($simdi -ge $bas -and $simdi -lt $son) }
        return ($simdi -ge $bas -or $simdi -lt $son)
    } catch { return $true }
}
function Dongu-Baslat {
    $script:SonBaslatma = Get-Date
    $baslat = Join-Path $VeriKok 'baslat.ps1'
    $ps = Join-Path $PSHOME 'powershell.exe'
    $arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $baslat + '"'
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    try {
        # conhost --headless: pencere hiç açılmaz (Windows Script Host gerektirmez).
        if (Test-Path -LiteralPath $conhost) { Start-Process -FilePath $conhost -ArgumentList ('--headless "' + $ps + '" ' + $arg) -WorkingDirectory $VeriKok -WindowStyle Hidden | Out-Null }
        else { Start-Process -FilePath $ps -ArgumentList $arg -WorkingDirectory $VeriKok -WindowStyle Hidden | Out-Null }
        Kayit 'Ajan döngüsü başlatıldı.'
    } catch { Kayit "Ajan döngüsü başlatılamadı: $($_.Exception.Message)" }
}
function Bekci {
    # Ofis açıkken döngü kapandıysa ya da yanıt vermiyorsa yeniden başlat (baslat.ps1'in kendi bekçisi donmuş süreci ayıklar).
    if (-not (Ofis-Niyeti)) { return }
    if (Test-Path -LiteralPath (Join-Path $VeriKok 'DURDUR')) { return }
    $d = Dongu-Durumu
    if ($d.canli) { return }
    $bekle = 120; if ($d.donmus) { $bekle = 600 }
    if (((Get-Date) - $SonBaslatma).TotalSeconds -ge $bekle) { Dongu-Baslat }
}

# ---------------------------------------------------------------- sohbet
function Sohbet-Klasoru { return (Klasor 'durum/sohbet') }
function Sohbet-Rol([string]$Rol) { if (-not $RolBilgi.Contains($Rol)) { throw 'HTTP:400:Geçersiz rol.' }; return $Rol }
function Sohbet-Calisiyor([string]$Rol) { return (SurecCanli (Json (Join-Path (Sohbet-Klasoru) "$Rol.pid"))) }
function Sohbet-Oku([string]$Rol, [int]$Son = 80) {
    $m = DisMetin (Join-Path (Sohbet-Klasoru) "$Rol.jsonl") 2097152
    $liste = New-Object Collections.Generic.List[object]
    foreach ($s in ($m -split "`n")) { if ($s.Trim()) { try { $liste.Add(($s | ConvertFrom-Json)) } catch {} } }
    $bas = [Math]::Max(0, $liste.Count - $Son)
    return ,@($liste.GetRange($bas, $liste.Count - $bas).ToArray())
}
function Sohbet-Son([string]$Rol) {
    $m = DisMetin (Join-Path (Sohbet-Klasoru) "$Rol.jsonl") 2097152
    $satirlar = @($m -split "`n" | Where-Object { $_.Trim() })
    if (-not $satirlar.Count) { return $null }
    try { return ($satirlar[-1] | ConvertFrom-Json) } catch { return $null }
}
function Sohbet-Baslat([string]$Rol) {
    $betik = Join-Path $PanelKok 'sohbet.ps1'
    $ps = Join-Path $PSHOME 'powershell.exe'
    $arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $betik + '" -Rol ' + $Rol
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if (Test-Path -LiteralPath $conhost) { Start-Process -FilePath $conhost -ArgumentList ('--headless "' + $ps + '" ' + $arg) -WorkingDirectory $VeriKok -WindowStyle Hidden | Out-Null }
    else { Start-Process -FilePath $ps -ArgumentList $arg -WorkingDirectory $VeriKok -WindowStyle Hidden | Out-Null }
}

# ---------------------------------------------------------------- durum
function Kadro($Dongu, $Gorevler) {
    $yol = YerelYol 'kadro'
    $k = Json $yol
    foreach ($anahtar in $RolBilgi.Keys) {
        $uye = @($k.uyeler | Where-Object { $_.anahtar -eq $anahtar } | Select-Object -First 1)
        $ad = $RolBilgi[$anahtar].ad; $aciklama = ''
        if ($uye.Count) { if ($uye[0].rol) { $ad = [string]$uye[0].rol }; $aciklama = [string]$uye[0].gorev }
        $calisiyor = $Dongu.rol -eq $anahtar
        # Bu istasyonda sırası gelen ya da yeniden denemeyi bekleyen işler
        $istasyon = @($Gorevler | Where-Object { $AsamaRol[[string]$_.asama] -eq $anahtar })
        $bekliyor = @($istasyon | Where-Object { $_.sonraki_deneme -and [int]$_.deneme -gt 0 }).Count -gt 0
        $son = Sohbet-Son $anahtar
        $durum = 'bosta'; if ($calisiyor) { $durum = 'calisiyor' }
        [ordered]@{
            anahtar = $anahtar; rol = $ad; gorev = $aciklama; renk = $RolBilgi[$anahtar].renk; durum = $durum
            aktif_gorev = $(if ($calisiyor) { $Dongu.gorev } else { '' }); arac = $(if ($calisiyor) { $Dongu.arac } else { '' })
            sirada = $istasyon.Count; bekliyor = $bekliyor
            sohbet = [ordered]@{ yaziyor = (Sohbet-Calisiyor $anahtar); son_zaman = $(if ($son) { $son.zaman } else { '' }); son_kim = $(if ($son) { $son.kim } else { '' }) }
        }
    }
}
function Olaylar($Gorevler) {
    $yol = Join-Path $VeriKok ('gunluk/yaratici-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    $m = DisMetin $yol 4194304
    if (-not $m) { return ,@() }
    $satirlar = @($m -split "`r?`n" | Where-Object { $_ -match '^\d{4}-\d\d-\d\d (\d\d:\d\d:\d\d) \[(\w+)\] (.*)$' -and $_ -notmatch 'sohbet-' } | Select-Object -Last 30)
    $no = @{}; foreach ($g in $Gorevler) { $no[[string]$g.id] = '#' + $g.no }
    $sonuc = New-Object Collections.Generic.List[object]
    foreach ($s in $satirlar) {
        if ($s -notmatch '^\d{4}-\d\d-\d\d (\d\d:\d\d:\d\d) \[(\w+)\] (.*)$') { continue }
        $saat = $Matches[1]; $seviye = $Matches[2]; $metin = $Matches[3]
        $metin = [regex]::Replace($metin, '\b\d{14}-[a-z0-9-]+-[a-f0-9]{8}\b', { param($x) if ($no.ContainsKey($x.Value)) { $no[$x.Value] } else { '#?' } })
        $sonuc.Add([ordered]@{ saat = $saat; seviye = $seviye; metin = $metin })
    }
    $sonuc.Reverse()
    return ,$sonuc.ToArray()
}
function Bildirimler {
    $m = DisMetin (Join-Path $VeriKok 'durum/bildirimler.jsonl') 1048576
    $liste = @(); foreach ($s in @($m -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 6)) { try { $liste += ($s | ConvertFrom-Json) } catch {} }
    [array]::Reverse($liste)
    return ,$liste
}
function Ana-Ofis($A) {
    $s = [ordered]@{ yapilandirildi = $false; bagli = $false; canli = $false; kapali = $false; durum = ''; panel = '' }
    $kok = Ana-Kok $A $null
    if (-not $kok) { return $s }
    $s.yapilandirildi = $true
    if (-not (Test-Path -LiteralPath (Join-Path $kok 'gorev-ekle.ps1') -PathType Leaf)) { return $s }
    $s.bagli = $true
    $k = DisJson (Join-Path $kok 'durum/kalp.json')
    if ($k) { try { $s.canli = (((Get-Date) - [datetime]$k.zaman).TotalMinutes -lt 15) -and $k.durum -ne 'durdu'; $s.durum = [string]$k.durum } catch {} }
    $s.kapali = Test-Path -LiteralPath (Join-Path $kok 'DURDUR')
    if ($IstekUzak) { $s.panel = $UzakAnaPanel }
    else { $sj = DisJson (Join-Path $kok 'ofis/sunucu.json'); if ($sj -and $sj.port) { $s.panel = 'http://127.0.0.1:' + [int]$sj.port + '/' } }
    return $s
}
function Durum {
    $a = Ayarlar
    $gorevler = Gorev-Listesi $a
    $dongu = Dongu-Durumu
    $sayac = Json (Join-Path $VeriKok 'durum/sayaclar.json')
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    $sayaclar = [ordered]@{ tarih = $bugun; claude = 0; codex = 0; tamamlanan = 0; sinir = [ordered]@{ claude = 0; codex = 0 } }
    if ($sayac -and $sayac.tarih -eq $bugun) { foreach ($ad in 'claude','codex','tamamlanan') { if ($sayac.PSObject.Properties[$ad]) { $sayaclar[$ad] = [int]$sayac.$ad } } }
    if ($a.gunluk_sinir) { foreach ($ad in 'claude','codex') { if ($a.gunluk_sinir.PSObject.Properties[$ad]) { $sayaclar.sinir[$ad] = [int]$a.gunluk_sinir.$ad } } }
    $durdur = Join-Path $VeriKok 'DURDUR'
    $durdurVar = Test-Path -LiteralPath $durdur
    $ofis = [ordered]@{
        acik = (Ofis-Niyeti) -and -not $durdurVar; durdur = $durdurVar; durdur_metni = $(if ($durdurVar) { (DisMetin $durdur 300).Trim() } else { '' })
        canli = $dongu.canli; donmus = $dongu.donmus; mesai = (Mesai $a); calisma_saatleri = [string]$a.dongu.calisma_saatleri
        revizyon_siniri = [int]$a.revizyon_siniri
    }
    return [ordered]@{
        zaman = (Get-Date).ToString('o'); gorevler = $gorevler; kalp = $dongu.kalp; sayaclar = $sayaclar
        kadro = @(Kadro $dongu $gorevler); asamalar = $Asamalar
        saglik = $dongu.saglik; aktif_ajan = $dongu.rol; aktif_gorev = $dongu.gorev; aktif_adim = $dongu.adim
        ofis = $ofis; ana_ofis = (Ana-Ofis $a); olaylar = (Olaylar $gorevler); bildirimler = (Bildirimler); uzak = $IstekUzak
    }
}

# ---------------------------------------------------------------- eylemler
function Alan($V, [string]$Ad, [int]$Sinir, [switch]$Zorunlu) {
    $deger = $V.$Ad
    if ($null -eq $deger) { $deger = '' }
    if ($deger -isnot [string] -or $deger.Length -gt $Sinir -or $deger -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { throw "HTTP:400:Geçersiz $Ad alanı." }
    if ($Zorunlu -and -not $deger.Trim()) { throw "HTTP:400:$Ad alanı gerekli." }
    return $deger.Trim()
}
function Eylem([string]$Yol, $V) {
    # Kullanıcı girdisi komut metnine çevrilmez. Sabit betiklere parametre bağlanır.
    try {
        $null = Metin (Join-Path $VeriKok 'durum/.panel-kontrol')
        switch ($Yol) {
            '/api/gorev-ekle' {
                $parametreler = @{ Konu = (Alan $V 'konu' 500 -Zorunlu); Alan = (Alan $V 'alan' 120); Proje = (Alan $V 'proje' 1024) }
                if (-not $parametreler.Alan) { $parametreler.Alan = 'genel' }
                # ReparsePoint kontrolü, görev oluşturma yolunda da uygulanır.
                $null = Metin (Join-Path $VeriKok 'gorevler/.panel-kontrol')
                $g = & (Join-Path $VeriKok 'proje-ekle.ps1') @parametreler
                Kayit 'Panelden yeni konu eklendi.'
                return @{ basarili = $true; id = $g.id }
            }
            { $_ -in @('/api/devam','/api/iptal') } {
                $id = Alan $V 'id' 120 -Zorunlu
                $null = Gorev $id
                $p = @{ Iptal = $id }; if ($Yol -eq '/api/devam') { $p = @{ Devam = $id } }
                $null = & (Join-Path $VeriKok 'durum.ps1') @p
                return @{ basarili = $true; id = $id }
            }
            '/api/ofis-ac' {
                Niyet-Yaz $true
                $durdur = Join-Path $VeriKok 'DURDUR'
                if (Test-Path -LiteralPath $durdur) { Remove-Item -LiteralPath $durdur -Force }
                $d = Dongu-Durumu
                if (-not $d.canli) { Dongu-Baslat }
                Kayit 'Ofis panelden açıldı.'
                return @{ basarili = $true; acik = $true }
            }
            '/api/ofis-kapat' {
                Niyet-Yaz $false
                [IO.File]::WriteAllText((Join-Path $VeriKok 'DURDUR'), ('Ofis kapatıldı (panel) ' + (Get-Date).ToString('dd.MM.yyyy HH:mm')), $Kodlama)
                Kayit 'Ofis panelden kapatıldı.'
                return @{ basarili = $true; acik = $false }
            }
            '/api/sohbet' {
                $rol = Sohbet-Rol (Alan $V 'rol' 30 -Zorunlu)
                $metin = Alan $V 'metin' 4000 -Zorunlu
                $calisan = @($RolBilgi.Keys | Where-Object { $_ -ne $rol -and (Sohbet-Calisiyor $_) }).Count
                $buCalisiyor = Sohbet-Calisiyor $rol
                if (-not $buCalisiyor -and $calisan -ge $EnFazlaSohbet) { throw "HTTP:429:Aynı anda en fazla $EnFazlaSohbet sohbet yanıtlanabilir; biraz sonra yeniden dene." }
                $satir = ConvertTo-Json -Compress -InputObject ([ordered]@{ zaman = (Get-Date).ToString('o'); kim = 'sen'; metin = $metin })
                [IO.File]::AppendAllText((Join-Path (Sohbet-Klasoru) "$rol.jsonl"), $satir + "`n", $Kodlama)
                if (-not $buCalisiyor) { Sohbet-Baslat $rol }
                return @{ basarili = $true; mesajlar = (Sohbet-Oku $rol); yaziyor = $true }
            }
            '/api/kapat' { $script:Kapat = $true; return @{ basarili = $true } }
            default { throw 'HTTP:404:Uç nokta bulunamadı.' }
        }
    } catch {
        if ($_.Exception.Message -like 'HTTP:*') { throw }
        throw ('HTTP:409:' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- HTTP
function Yanit($Akis, [int]$Kod, [string]$Tur, $Icerik, [string]$Ek = '', [string]$Onbellek = 'no-store') {
    if ($Icerik -is [byte[]]) { $govde = $Icerik } else { $govde = $Kodlama.GetBytes([string]$Icerik) }
    $baslik = "HTTP/1.1 $Kod Response`r`nContent-Type: $Tur`r`nContent-Length: $($govde.Length)`r`nConnection: close`r`nCache-Control: $Onbellek`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nX-Frame-Options: DENY`r`n$Ek`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($baslik)
    $Akis.Write($b, 0, $b.Length); $Akis.Write($govde, 0, $govde.Length)
}
function YanitJson($Akis, [int]$Kod, $Veri) { Yanit $Akis $Kod 'application/json; charset=utf-8' (ConvertTo-Json -InputObject $Veri -Depth 16 -Compress) }
function IstekCoz([IO.MemoryStream]$Tampon) {
    if ($Tampon.Length -gt 81920) { throw 'HTTP:413:İstek çok büyük.' }
    $bayt = $Tampon.ToArray()
    $metin = [Text.Encoding]::GetEncoding(28591).GetString($bayt)
    $son = $metin.IndexOf("`r`n`r`n")
    if ($son -lt 0) { if ($Tampon.Length -gt 16384) { throw 'HTTP:431:Başlık çok büyük.' }; return $null }
    if ($son -gt 16384) { throw 'HTTP:431:Başlık çok büyük.' }
    $satir = $metin.Substring(0, $son) -split "`r`n"
    if ($satir[0] -notmatch '^(GET|POST) (/[^ ]*) HTTP/1\.[01]$') { throw 'HTTP:405:Desteklenmeyen HTTP isteği.' }
    $yontem = $Matches[1]; $hedef = $Matches[2]; $basliklar = @{}
    foreach ($s in $satir[1..($satir.Count - 1)]) {
        if ($s -notmatch '^([A-Za-z0-9-]+):[ \t]*(.*)$') { throw 'HTTP:400:Bozuk başlık.' }
        $ad = $Matches[1].ToLowerInvariant(); $deger = $Matches[2].Trim()
        if ($basliklar.ContainsKey($ad)) { throw 'HTTP:400:Yinelenen başlık.' }
        $basliklar[$ad] = $deger
    }
    if ($basliklar.ContainsKey('transfer-encoding') -or $basliklar.ContainsKey('expect')) { throw 'HTTP:400:Desteklenmeyen aktarım.' }
    $uzunluk = 0
    if ($basliklar.ContainsKey('content-length')) {
        if ($basliklar['content-length'] -notmatch '^\d{1,8}$' -or -not [int]::TryParse($basliklar['content-length'], [ref]$uzunluk)) { throw 'HTTP:400:Geçersiz içerik uzunluğu.' }
    }
    if ($uzunluk -gt 65536) { throw 'HTTP:413:İstek çok büyük.' }
    if ($bayt.Length -lt ($son + 4 + $uzunluk)) { return $null }
    return @{ yontem = $yontem; hedef = $hedef; basliklar = $basliklar; govde = $Kodlama.GetString($bayt, $son + 4, $uzunluk) }
}
function Sorgu([string]$Metin, [string]$Ad) {
    foreach ($p in ($Metin -split '&')) { if ($p -match ('^' + [regex]::Escape($Ad) + '=([^&]*)$')) { return [Uri]::UnescapeDataString($Matches[1]) } }
    return ''
}
function Manifest($Akis) {
    $m = [ordered]@{
        name = 'Creativity Office'; short_name = 'Creativity'; description = 'Yaratıcı ofis: fikirden POC''ye canlı stüdyo'
        start_url = '/'; scope = '/'; display = 'standalone'; background_color = '#1b1524'; theme_color = '#1b1524'; lang = 'tr'
        icons = @([ordered]@{ src = '/simge-192.png'; sizes = '192x192'; type = 'image/png' }, [ordered]@{ src = '/simge-512.png'; sizes = '512x512'; type = 'image/png'; purpose = 'any maskable' })
    }
    Yanit $Akis 200 'application/manifest+json; charset=utf-8' (ConvertTo-Json -InputObject $m -Depth 5 -Compress) '' 'no-cache'
}
function IstekIsle($Akis, $I) {
    $h = $I.basliklar
    $hostH = ([string]$h['host']).ToLowerInvariant()
    $yerelHost = @("127.0.0.1:$Port", "localhost:$Port") -contains $hostH
    $uzakHost = (-not $yerelHost) -and $UzakHostlar.Count -gt 0 -and ($UzakHostlar -contains ($hostH -replace ':\d{1,5}$', ''))
    if (-not $yerelHost -and -not $uzakHost) {
        if ($hostH -and $script:SonReddedilenHost -ne $hostH) { $script:SonReddedilenHost = $hostH; Kayit 'Bilinmeyen Host başlığı reddedildi.' }
        throw 'HTTP:403:Yalnızca yerel Host kabul edilir.'
    }
    # Telefondan (Tailscale serve üzerinden) gelen istek: yalnızca uzak.json'daki Tailscale hesaplarına izin ver.
    $tsKim = ([string]$h['tailscale-user-login']).Trim().ToLowerInvariant()
    if ($uzakHost -or $tsKim) {
        if (-not $tsKim -or ($UzakKullanicilar.Count -gt 0 -and $UzakKullanicilar -notcontains $tsKim)) { throw 'HTTP:403:Bu hesaba izin verilmiyor.' }
    }
    $script:IstekUzak = [bool]$uzakHost
    $koken = 'http://' + $hostH; if ($uzakHost) { $koken = 'https://' + $hostH }
    if ($h['origin'] -and $h['origin'] -cne $koken) { throw 'HTTP:403:Origin reddedildi.' }
    if ($h['sec-fetch-site'] -and $h['sec-fetch-site'] -notin @('same-origin','none')) { throw 'HTTP:403:Siteler arası istek reddedildi.' }
    $parca = $I.hedef.Split('?', 2); $yol = $parca[0]; $sorgu = ''; if ($parca.Count -eq 2) { $sorgu = $parca[1] }
    if ($I.yontem -eq 'GET' -and $yol -eq '/') {
        $nonce = [guid]::NewGuid().ToString('N')
        $html = (Metin (Join-Path $PanelKok 'panel.html') 2MB).Replace('__OTURUM__', $Oturum).Replace('__NONCE__', $nonce)
        $csp = "Content-Security-Policy: default-src 'none'; script-src 'nonce-$nonce'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`r`n"
        Yanit $Akis 200 'text/html; charset=utf-8' $html $csp
        return
    }
    if ($I.yontem -eq 'GET' -and $yol -eq '/manifest.webmanifest') { Manifest $Akis; return }
    if ($I.yontem -eq 'GET' -and $yol -match '^/simge-(180|192|512)\.png$') {
        $f = Join-Path $PanelKok "simge-$($Matches[1]).png"
        if (-not [IO.File]::Exists($f)) { throw 'HTTP:404:Simge yok.' }
        Yanit $Akis 200 'image/png' ([IO.File]::ReadAllBytes($f)) '' 'max-age=86400'
        return
    }
    if (-not $yol.StartsWith('/api/')) { throw 'HTTP:404:Bulunamadı.' }
    if ($h['x-oturum'] -cne $Oturum) { throw 'HTTP:401:Oturum geçersiz; sayfayı yenileyin.' }
    if ($I.yontem -eq 'GET') {
        switch ($yol) {
            '/api/durum' { YanitJson $Akis 200 (Durum); return }
            '/api/gorev' {
                $id = Sorgu $sorgu 'id'
                $g = Gorev $id
                $gk = GorevYolu $id
                $belgeler = [ordered]@{}
                foreach ($ad in @('gorev.md','fikir.md','elestiri.md','poc-plan.md','maliyet.md','karar.md','teslim.json','ana-ofis-ciktisi.md','uygulama-ciktisi.md','puanlama.md','sonuc.md')) { $belgeler[$ad] = Metin (Join-Path $gk $ad) }
                $ham = Json (Join-Path $gk 'durum.json')
                $g['gecmis'] = @($ham.gecmis)
                $g['geri_bildirimler'] = @($ham.geri_bildirimler)
                $g['belgeler'] = $belgeler
                YanitJson $Akis 200 $g; return
            }
            '/api/sohbet' {
                $rol = Sohbet-Rol (Sorgu $sorgu 'rol')
                YanitJson $Akis 200 ([ordered]@{ rol = $rol; mesajlar = (Sohbet-Oku $rol); yaziyor = (Sohbet-Calisiyor $rol) }); return
            }
            default { throw 'HTTP:404:Uç nokta bulunamadı.' }
        }
    }
    if ($h['content-type'] -notmatch '^application/json(?:\s*;.*)?$') { throw 'HTTP:415:JSON bekleniyor.' }
    try { $v = ConvertFrom-Json -InputObject $I.govde -ErrorAction Stop } catch { throw 'HTTP:400:Geçersiz JSON.' }
    if ($v -isnot [pscustomobject]) { throw 'HTTP:400:JSON nesnesi bekleniyor.' }
    YanitJson $Akis 200 (Eylem $yol $v)
}

# ---------------------------------------------------------------- başlat / durdur
if ($Durdur) {
    $bilgi = Json $SunucuYolu
    if (-not $bilgi -or -not $bilgi.port) { Write-Output 'Panel çalışmıyor.'; return }
    # Anahtar diskte tutulmaz; yerel panelden alınıp aynı güvenli API kullanılır.
    $adres = 'http://127.0.0.1:' + [int]$bilgi.port
    $sayfa = Invoke-WebRequest "$adres/" -UseBasicParsing -TimeoutSec 5
    if ($sayfa.Content -notmatch 'const OTURUM = "([a-f0-9]{32})";') { throw 'Panel oturumu doğrulanamadı.' }
    $null = Invoke-WebRequest "$adres/api/kapat" -UseBasicParsing -Method Post -ContentType 'application/json' -Headers @{ 'X-Oturum' = $Matches[1] } -Body '{}' -TimeoutSec 5
    Write-Output 'Panel durduruldu.'; return
}
# Uzaktan erişim (telefon): ofis\uzak.json { "hostlar": ["bilgisayar.tailXXXX.ts.net"], "kullanicilar": ["hesap@ornek.com"], "ana_panel": "https://..." }
$script:UzakHostlar = @(); $script:UzakKullanicilar = @(); $script:UzakAnaPanel = ''
$uzak = Json (Join-Path $PanelKok 'uzak.json')
if ($uzak) {
    $script:UzakHostlar = @(@($uzak.hostlar) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().TrimEnd('.').ToLowerInvariant() })
    $script:UzakKullanicilar = @(@($uzak.kullanicilar) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($uzak.ana_panel -and [string]$uzak.ana_panel -match '^https://[a-z0-9.-]+(:\d+)?/$') { $script:UzakAnaPanel = [string]$uzak.ana_panel }
    if ($UzakHostlar.Count -gt 0 -and $BosKapanDk -gt 0) { $BosKapanDk = 0 }
}
$mutex = [Threading.Mutex]::new($false, 'Local\YaraticiOfisPaneli')
$sahip = $false; $dinleyici = $null
$baglantilar = New-Object Collections.Generic.List[object]
try {
    try { $sahip = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sahip = $true }
    if (-not $sahip) {
        $mevcut = Json $SunucuYolu; $p = $Port; if ($mevcut.port) { $p = [int]$mevcut.port }
        Write-Output "Creativity Office paneli zaten çalışıyor: http://127.0.0.1:$p/"
        if ($Ac) { Start-Process "http://127.0.0.1:$p/" }
        return
    }
    # Telefona eklenen uygulama simgeleri yoksa üret (System.Drawing; ağ gerekmez).
    try { if (-not (Test-Path -LiteralPath (Join-Path $PanelKok 'simge-192.png'))) { . (Join-Path $PanelKok 'simge.ps1'); Simge-Uret $PanelKok } } catch { Kayit 'Simgeler üretilemedi.' }
    $script:Oturum = [guid]::NewGuid().ToString('N')
    $dinleyici = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    $dinleyici.ExclusiveAddressUse = $true
    $dinleyici.Start()
    [IO.File]::WriteAllText($SunucuYolu, (@{ pid = $PID; port = $Port; baslangic = (Get-Date).ToString('o') } | ConvertTo-Json), $Kodlama)
    Kayit "Creativity Office: http://127.0.0.1:$Port/ (uzak: $($UzakHostlar -join ', '))"
    if ($Ac) { Start-Process "http://127.0.0.1:$Port/" }
    $sonIstek = Get-Date; $sonBekci = [datetime]::MinValue
    while (-not $Kapat) {
        while ($dinleyici.Pending()) {
            $c = $dinleyici.AcceptTcpClient()
            if ($baglantilar.Count -ge 32) { $c.Close(); continue }
            $c.SendTimeout = 4000
            $baglantilar.Add(@{ istemci = $c; akis = $c.GetStream(); tampon = [IO.MemoryStream]::new(); bas = (Get-Date) })
        }
        for ($i = $baglantilar.Count - 1; $i -ge 0; $i--) {
            $b = $baglantilar[$i]; $bitti = $false
            try {
                if (((Get-Date) - $b.bas).TotalSeconds -gt 10) { $bitti = $true }
                elseif ($b.istemci.Available -gt 0) {
                    $buf = New-Object byte[] ([Math]::Min(8192, $b.istemci.Available))
                    $n = $b.akis.Read($buf, 0, $buf.Length); $b.tampon.Write($buf, 0, $n)
                    $istek = IstekCoz $b.tampon
                    if ($istek) { $sonIstek = Get-Date; $script:IstekUzak = $false; IstekIsle $b.akis $istek; $bitti = $true }
                } elseif ($b.istemci.Client.Poll(0, [Net.Sockets.SelectMode]::SelectRead)) { $bitti = $true }
            } catch {
                $kod = 500; $mesaj = 'Sunucu isteği tamamlayamadı.'
                if ($_.Exception.Message -match '^HTTP:(\d{3}):(.*)$') { $kod = [int]$Matches[1]; $mesaj = $Matches[2] }
                else { Kayit "İstek işlenirken hata oluştu: $($_.Exception.Message)" }
                try { YanitJson $b.akis $kod @{ hata = $mesaj } } catch {}
                $bitti = $true
            }
            if ($bitti) {
                try { $b.istemci.Client.Shutdown([Net.Sockets.SocketShutdown]::Send) } catch {}
                $b.istemci.Close(); $b.tampon.Dispose(); $baglantilar.RemoveAt($i)
            }
        }
        if (((Get-Date) - $sonBekci).TotalSeconds -ge 20) { $sonBekci = Get-Date; try { Bekci } catch { Kayit "Bekçi hatası: $($_.Exception.Message)" } }
        if ($BosKapanDk -gt 0 -and ((Get-Date) - $sonIstek).TotalMinutes -ge $BosKapanDk -and -not (Ofis-Niyeti)) { break }
        Start-Sleep -Milliseconds 25
    }
} finally {
    foreach ($b in $baglantilar) { $b.istemci.Close(); $b.tampon.Dispose() }
    if ($dinleyici) { $dinleyici.Stop() }
    if ($sahip) {
        if (Test-Path -LiteralPath $SunucuYolu) { Remove-Item -LiteralPath $SunucuYolu -Force }
        Kayit 'Panel durdu.'
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
