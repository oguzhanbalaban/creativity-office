<#
Creativity Office yerel paneli. HTTP.sys/URL ACL veya yönetici izni gerektirmemek
için referans AI Ofis gibi TcpListener kullanır; yalnızca IPv4 loopback dinler.
Oturum anahtarı yalnızca bellekte ve sunulan HTML'dedir, diske kaydedilmez.
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
$script:Asamalar = @('yeni','fikir','elestiri','poc_plan','maliyet','karar','teslim','bekleme','puanlama','tamam')
$script:Roller = @{ fikir='fikirci'; elestiri='elestirmen'; poc_plan='planlamaci'; maliyet='maliyet'; karar='karar-verici'; puanlama='puanlayici' }

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
    # Junction/symlink üzerinden görev kökü dışındaki dosyalar sunulmaz.
    $aday = $Yol
    while ($aday -and $aday.Length -ge $VeriKok.Length) {
        if ((Test-Path -LiteralPath $aday) -and ((Get-Item -LiteralPath $aday -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'HTTP:400:Bağlantılı dosya veya klasör kullanılamaz.' }
        if ($aday -eq $VeriKok) { break }
        $aday = Split-Path -Parent $aday
    }
    if (-not [IO.File]::Exists($Yol)) { return '' }
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
function GorevYolu([string]$Id) {
    if ($Id -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,119}$') { throw 'HTTP:400:Geçersiz görev kimliği.' }
    return (Join-Path (Join-Path $VeriKok 'gorevler') $Id)
}
function Gorev([string]$Id) {
    $yol = GorevYolu $Id
    $g = Json (Join-Path $yol 'durum.json')
    if (-not $g) { throw 'HTTP:404:Görev bulunamadı veya durum dosyası okunamıyor.' }
    # JSON içindeki kimliğe değil doğrulanmış klasör adına güvenilir.
    return [ordered]@{ id=$Id; baslik=$g.baslik; alan=$g.alan; proje=$g.proje; asama=$g.asama; takildi_asama=$g.takildi_asama; revizyon=$g.revizyon; puan=$g.puan; son_hata=$g.son_hata; guncelleme=$g.guncelleme; gecmis=@($g.gecmis) }
}
function Kadro {
    $yol = Join-Path $VeriKok 'kadro.json'
    if ((Test-Path -LiteralPath (Join-Path $VeriKok 'kadro.yerel.json')) -or (Test-Path -LiteralPath (Join-Path $VeriKok 'kadro.yerel.json.bak'))) { $yol = Join-Path $VeriKok 'kadro.yerel.json' }
    $k = Json $yol
    $adlar = [ordered]@{ fikirci='Fikir Üretici'; elestirmen='Eleştirmen'; planlamaci='POC Planlayıcı'; maliyet='Maliyet Analisti'; 'karar-verici'='Karar Verici'; puanlayici='Puanlayıcı' }
    foreach ($anahtar in $adlar.Keys) {
        $uye = @($k.uyeler | Where-Object { $_.anahtar -eq $anahtar } | Select-Object -First 1)
        $ad = $adlar[$anahtar]; $aciklama = ''
        if ($uye.Count) { if ($uye[0].rol) { $ad = $uye[0].rol }; $aciklama = $uye[0].gorev }
        [ordered]@{ anahtar=$anahtar; rol=$ad; gorev=$aciklama }
    }
}
function Durum {
    $gorevler = @(
        foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $VeriKok 'gorevler') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            try { Gorev $d.Name } catch { Kayit 'Okunamayan bir görev atlandı.' }
        }
    )
    $kalp = Json (Join-Path $VeriKok 'durum/kalp.json')
    $canli = $false
    try {
        $yas = ((Get-Date) - [datetime]$kalp.zaman).TotalSeconds
        $surec = Get-Process -Id ([int]$kalp.pid) -ErrorAction Stop
        $canli = $kalp.durum -ne 'durdu' -and $yas -ge -5 -and $yas -lt 90 -and
            [Math]::Abs(($surec.StartTime - [datetime]$kalp.baslangic).TotalSeconds) -lt 2
    } catch {}
    $rol = ''; $aktifId = ''; $adim = ''; $saglik = 'durdu'
    if ($canli) {
        $saglik = 'bosta'
        # Bekleme kalbi önceki görev/adım bilgisini taşıyabilir; etkin sayılmaz.
        if ($kalp.durum -eq 'adım' -or $kalp.durum -match ' çalışıyor$') {
            $saglik = 'calisiyor'; $aktifId = [string]$kalp.gorev; $adim = [string]$kalp.adim
            $rol = [string]$Roller[$adim]
        }
    }
    $kadro = @(Kadro)
    foreach ($u in $kadro) { $u['durum'] = 'bosta'; if ($rol -eq $u.anahtar) { $u['durum'] = 'calisiyor' } }
    return [ordered]@{ gorevler=$gorevler; kalp=$kalp; sayaclar=(Json (Join-Path $VeriKok 'durum/sayaclar.json')); kadro=$kadro; asamalar=$Asamalar; saglik=$saglik; aktif_ajan=$rol; aktif_gorev=$aktifId; aktif_adim=$adim; zaman=(Get-Date).ToString('o') }
}
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
                $parametreler = @{ Konu=(Alan $V 'konu' 500 -Zorunlu); Alan=(Alan $V 'alan' 120); Proje=(Alan $V 'proje' 1024) }
                if (-not $parametreler.Alan) { $parametreler.Alan = 'genel' }
                # ReparsePoint kontrolü, görev oluşturma yolunda da uygulanır.
                $null = Metin (Join-Path $VeriKok 'gorevler/.panel-kontrol')
                $g = & (Join-Path $VeriKok 'proje-ekle.ps1') @parametreler
                return @{ basarili=$true; id=$g.id }
            }
            { $_ -in @('/api/devam','/api/iptal') } {
                $id = Alan $V 'id' 120 -Zorunlu
                $null = Gorev $id
                $p = @{ Iptal=$id }; if ($Yol -eq '/api/devam') { $p = @{ Devam=$id } }
                $null = & (Join-Path $VeriKok 'durum.ps1') @p
                return @{ basarili=$true; id=$id }
            }
            '/api/kapat' { $script:Kapat = $true; return @{ basarili=$true } }
            default { throw 'HTTP:404:Uç nokta bulunamadı.' }
        }
    } catch {
        if ($_.Exception.Message -like 'HTTP:*') { throw }
        throw ('HTTP:409:' + $_.Exception.Message)
    }
}
function Yanit($Akis, [int]$Kod, [string]$Tur, [string]$Icerik, [string]$Ek = '') {
    $govde = $Kodlama.GetBytes($Icerik)
    $baslik = "HTTP/1.1 $Kod Response`r`nContent-Type: $Tur`r`nContent-Length: $($govde.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nX-Frame-Options: DENY`r`n$Ek`r`n"
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
    $satir = $metin.Substring(0,$son) -split "`r`n"
    if ($satir[0] -notmatch '^(GET|POST) (/[^ ]*) HTTP/1\.[01]$') { throw 'HTTP:405:Desteklenmeyen HTTP isteği.' }
    $yontem = $Matches[1]; $hedef = $Matches[2]; $basliklar = @{}
    foreach ($s in $satir[1..($satir.Count-1)]) {
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
    return @{ yontem=$yontem; hedef=$hedef; basliklar=$basliklar; govde=$Kodlama.GetString($bayt,$son+4,$uzunluk) }
}
function IstekIsle($Akis, $I) {
    $h = $I.basliklar
    if (@("127.0.0.1:$Port", "localhost:$Port") -notcontains $h['host']) { throw 'HTTP:403:Yalnızca yerel Host kabul edilir.' }
    if ($h['origin'] -and $h['origin'] -cne ('http://' + $h['host'])) { throw 'HTTP:403:Origin reddedildi.' }
    if ($h['sec-fetch-site'] -and $h['sec-fetch-site'] -notin @('same-origin','none')) { throw 'HTTP:403:Siteler arası istek reddedildi.' }
    $parca = $I.hedef.Split('?',2); $yol = $parca[0]
    if ($I.yontem -eq 'GET' -and $yol -eq '/') {
        $nonce = [guid]::NewGuid().ToString('N')
        $html = (Metin (Join-Path $PanelKok 'panel.html') 1MB).Replace('__OTURUM__',$Oturum).Replace('__NONCE__',$nonce)
        $csp = "Content-Security-Policy: default-src 'none'; script-src 'nonce-$nonce'; style-src 'nonce-$nonce'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`r`n"
        Yanit $Akis 200 'text/html; charset=utf-8' $html $csp
        return
    }
    if (-not $yol.StartsWith('/api/')) { throw 'HTTP:404:Bulunamadı.' }
    if ($h['x-oturum'] -cne $Oturum) { throw 'HTTP:401:Oturum geçersiz; sayfayı yenileyin.' }
    if ($I.yontem -eq 'GET') {
        switch ($yol) {
            '/api/durum' { YanitJson $Akis 200 (Durum); return }
            '/api/gorev' {
                $id = ''
                if ($parca.Count -eq 2 -and $parca[1] -match '^id=([^&]+)$') { $id = [Uri]::UnescapeDataString($Matches[1]) }
                $g = Gorev $id
                $belgeler = [ordered]@{}
                foreach ($ad in @('gorev.md','fikir.md','elestiri.md','poc-plan.md','maliyet.md','karar.md','teslim.json','puanlama.md','sonuc.md')) { $belgeler[$ad] = Metin (Join-Path (GorevYolu $id) $ad) }
                $g['belgeler'] = $belgeler
                YanitJson $Akis 200 $g; return
            }
            default { throw 'HTTP:404:Uç nokta bulunamadı.' }
        }
    }
    if ($h['content-type'] -notmatch '^application/json(?:\s*;.*)?$') { throw 'HTTP:415:JSON bekleniyor.' }
    try { $v = ConvertFrom-Json -InputObject $I.govde -ErrorAction Stop } catch { throw 'HTTP:400:Geçersiz JSON.' }
    if ($v -isnot [pscustomobject]) { throw 'HTTP:400:JSON nesnesi bekleniyor.' }
    YanitJson $Akis 200 (Eylem $yol $v)
}

if ($Durdur) {
    $bilgi = Json $SunucuYolu
    if (-not $bilgi -or -not $bilgi.port) { Write-Output 'Panel çalışmıyor.'; return }
    # Anahtar diskte tutulmaz; yerel panelden alınıp aynı güvenli API kullanılır.
    $adres = 'http://127.0.0.1:' + [int]$bilgi.port
    $sayfa = Invoke-WebRequest "$adres/" -UseBasicParsing -TimeoutSec 5
    if ($sayfa.Content -notmatch 'const OTURUM = "([a-f0-9]{32})";') { throw 'Panel oturumu doğrulanamadı.' }
    $null = Invoke-WebRequest "$adres/api/kapat" -UseBasicParsing -Method Post -ContentType 'application/json' -Headers @{ 'X-Oturum'=$Matches[1] } -Body '{}' -TimeoutSec 5
    Write-Output 'Panel durduruldu.'; return
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
    $script:Oturum = [guid]::NewGuid().ToString('N')
    $dinleyici = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    $dinleyici.ExclusiveAddressUse = $true
    $dinleyici.Start()
    [IO.File]::WriteAllText($SunucuYolu, (@{ pid=$PID; port=$Port; baslangic=(Get-Date).ToString('o') } | ConvertTo-Json), $Kodlama)
    Kayit "Creativity Office: http://127.0.0.1:$Port/ — Ctrl+C ile durdurun."
    if ($Ac) { Start-Process "http://127.0.0.1:$Port/" }
    $sonIstek = Get-Date
    while (-not $Kapat) {
        while ($dinleyici.Pending()) {
            $c = $dinleyici.AcceptTcpClient()
            if ($baglantilar.Count -ge 32) { $c.Close(); continue }
            $c.SendTimeout = 2000
            $baglantilar.Add(@{ istemci=$c; akis=$c.GetStream(); tampon=[IO.MemoryStream]::new(); bas=(Get-Date) })
        }
        for ($i = $baglantilar.Count-1; $i -ge 0; $i--) {
            $b = $baglantilar[$i]; $bitti = $false
            try {
                if (((Get-Date) - $b.bas).TotalSeconds -gt 10) { $bitti = $true }
                elseif ($b.istemci.Available -gt 0) {
                    $buf = New-Object byte[] ([Math]::Min(8192,$b.istemci.Available))
                    $n = $b.akis.Read($buf,0,$buf.Length); $b.tampon.Write($buf,0,$n)
                    $istek = IstekCoz $b.tampon
                    if ($istek) { $sonIstek = Get-Date; IstekIsle $b.akis $istek; $bitti = $true }
                } elseif ($b.istemci.Client.Poll(0,[Net.Sockets.SelectMode]::SelectRead)) { $bitti = $true }
            } catch {
                $kod = 500; $mesaj = 'Sunucu isteği tamamlayamadı.'
                if ($_.Exception.Message -match '^HTTP:(\d{3}):(.*)$') { $kod = [int]$Matches[1]; $mesaj = $Matches[2] }
                else { Kayit 'İstek işlenirken hata oluştu.' }
                try { YanitJson $b.akis $kod @{ hata=$mesaj } } catch {}
                $bitti = $true
            }
            if ($bitti) {
                try { $b.istemci.Client.Shutdown([Net.Sockets.SocketShutdown]::Send) } catch {}
                $b.istemci.Close(); $b.tampon.Dispose(); $baglantilar.RemoveAt($i)
            }
        }
        if ($BosKapanDk -gt 0 -and ((Get-Date)-$sonIstek).TotalMinutes -ge $BosKapanDk) { break }
        Start-Sleep -Milliseconds 20
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
