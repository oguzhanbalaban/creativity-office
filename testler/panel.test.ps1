# Çevrimdışı HTTP bütünleşmesi: yalnızca geçici kopya ve IPv4 loopback kullanılır.
$ErrorActionPreference = 'Stop'
$kaynak = Split-Path -Parent $PSScriptRoot
$testTabani = Join-Path $kaynak '.test-calisma'
$testKok = Join-Path $testTabani ([guid]::NewGuid().ToString('N'))
$script:kontrol = 0
$script:anahtar = ''
$utf8Test = New-Object Text.UTF8Encoding $false
$sunucu = $null; $onBaglanti = $null
function Dogrula([bool]$Kosul, [string]$Mesaj) {
    if (-not $Kosul) { throw "BAŞARISIZ: $Mesaj" }
    $script:kontrol++; Write-Host "OK $script:kontrol - $Mesaj"
}
function Istek([string]$Yol, [string]$Yontem = 'GET', [string]$Govde = '', [hashtable]$Baslik = @{}, [switch]$Anahtarsiz) {
    $c = [Net.Sockets.TcpClient]::new()
    try {
        $c.Connect([Net.IPAddress]::Loopback,$script:testPort)
        $c.ReceiveTimeout = 5000; $c.SendTimeout = 5000
        $h = @{ Host="127.0.0.1:$script:testPort"; Connection='close' }
        if (-not $Anahtarsiz -and $script:anahtar) { $h['X-Oturum'] = $script:anahtar }
        foreach ($k in $Baslik.Keys) { $h[$k] = $Baslik[$k] }
        $gb = $utf8Test.GetBytes($Govde)
        if ($Yontem -eq 'POST') { $h['Content-Type'] = 'application/json'; $h['Content-Length'] = $gb.Length }
        $s = "$Yontem $Yol HTTP/1.1`r`n"
        foreach ($k in $h.Keys) { $s += "${k}: $($h[$k])`r`n" }
        $b = [Text.Encoding]::ASCII.GetBytes($s + "`r`n")
        $akis = $c.GetStream(); $akis.Write($b,0,$b.Length)
        if ($gb.Length) { $akis.Write($gb,0,$gb.Length) }
        $cevap = [IO.MemoryStream]::new()
        try {
            $buf = New-Object byte[] 8192
            while ($true) {
                $n = $akis.Read($buf,0,$buf.Length)
                if ($n -eq 0) { break }
                $cevap.Write($buf,0,$n)
                $ham = $cevap.ToArray()
                $ascii = [Text.Encoding]::GetEncoding(28591).GetString($ham)
                $basSon = $ascii.IndexOf("`r`n`r`n")
                if ($basSon -ge 0 -and $ascii.Substring(0,$basSon) -match 'Content-Length: (\d+)') {
                    if ($ham.Length -ge $basSon+4+[int]$Matches[1]) { break }
                }
            }
            $yanit = $utf8Test.GetString($cevap.ToArray())
        } finally { $cevap.Dispose() }
        $ayir = $yanit.IndexOf("`r`n`r`n")
        if ($ayir -lt 0 -or $yanit -notmatch '^HTTP/1.1 (\d{3}) ') { throw 'Geçersiz HTTP yanıtı.' }
        return @{ kod=[int]$Matches[1]; baslik=$yanit.Substring(0,$ayir); govde=$yanit.Substring($ayir+4) }
    } finally { $c.Dispose() }
}
function PanelBaslat {
    $psArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"' + (Join-Path $testKok 'ofis/ofis.ps1') + '"'),'-Port',$script:testPort,'-BosKapanDk','0')
    $script:sunucu = Start-Process -FilePath "$PSHOME/powershell.exe" -ArgumentList $psArgs -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $testKok 'stderr.log')
    $hazir = $false
    for ($i=0;$i -lt 60;$i++) {
        if ($sunucu.HasExited) { throw ('Sunucu erken kapandı: ' + [IO.File]::ReadAllText((Join-Path $testKok 'stderr.log'))) }
        try { $r = Istek '/' -Anahtarsiz; if ($r.kod -eq 200) { $hazir=$true; break } } catch {}
        Start-Sleep -Milliseconds 100
    }
    Dogrula $hazir 'Sunucu loopback üzerinde yanıt veriyor'
    return $r
}
function JsonYaz([string]$Yol,$Veri) { [IO.File]::WriteAllText($Yol,($Veri | ConvertTo-Json -Depth 12),$utf8Test) }
try {
    New-Item -ItemType Directory -Path $testKok -Force | Out-Null
    foreach ($ad in @('proje-ekle.ps1','durum.ps1','ortak.ps1','ayarlar.json','kadro.json')) { Copy-Item -LiteralPath (Join-Path $kaynak $ad) -Destination $testKok }
    Copy-Item -LiteralPath (Join-Path $kaynak 'ofis') -Destination $testKok -Recurse
    $betik = Join-Path $testKok 'ofis/ofis.ps1'
    # Test gerçek bir panelin mutex'ine veya çalışma verilerine dokunmaz.
    [IO.File]::WriteAllText($betik,([IO.File]::ReadAllText($betik).Replace('Local\YaraticiOfisPaneli',('Local\YaraticiPanelTest' + [guid]::NewGuid().ToString('N')))),(New-Object Text.UTF8Encoding $true))
    $portSec = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $portSec.Start(); $script:testPort = $portSec.LocalEndpoint.Port; $portSec.Stop()
    $sayfa = PanelBaslat
    Dogrula ($sayfa.govde -match 'const OTURUM = "([a-f0-9]{32})";') 'Oturum anahtarı HTML içinde üretiliyor'
    $script:anahtar = $Matches[1]
    Dogrula ($sayfa.govde -notmatch '__OTURUM__|__NONCE__') 'HTML şablonları dolduruluyor'
    Dogrula ($sayfa.baslik -match 'Content-Security-Policy:' -and $sayfa.baslik -match 'Cache-Control: no-store') 'CSP ve önbellek koruması var'
    Dogrula (-not [IO.File]::ReadAllText((Join-Path $testKok 'ofis/sunucu.json')).Contains($anahtar)) 'Oturum anahtarı diske kaydedilmiyor'
    $r = Istek '/api/durum' -Anahtarsiz
    Dogrula ($r.kod -eq 401) 'GET API de oturum gerektiriyor'
    $r = Istek '/api/durum' -Baslik @{ 'X-Oturum'='yanlis' }
    Dogrula ($r.kod -eq 401) 'Yanlış oturum reddediliyor'
    $r = Istek '/' -Baslik @{ Host='saldirgan.example' }
    Dogrula ($r.kod -eq 403) 'DNS rebinding Host başlığı reddediliyor'
    $r = Istek '/' -Baslik @{ Origin='https://saldirgan.example' }
    Dogrula ($r.kod -eq 403) 'Yabancı Origin panelden de reddediliyor'
    $r = Istek '/api/durum' -Baslik @{ 'Sec-Fetch-Site'='cross-site' }
    Dogrula ($r.kod -eq 403) 'Cross-site API erişimi reddediliyor'
    $r = Istek '/api/durum' -Baslik @{ Host="localhost:$testPort"; Origin="http://localhost:$testPort"; 'Sec-Fetch-Site'='same-origin' }
    Dogrula ($r.kod -eq 200) 'localhost Host ve eşleşen Origin kabul ediliyor'
    $r = Istek '/api/gorev-ekle' 'POST' '{"konu":"Test"}' -Anahtarsiz
    Dogrula ($r.kod -eq 401) 'POST API oturumsuz görev oluşturmuyor'
    $r = Istek '/api/gorev-ekle' 'POST' '{bozuk'
    Dogrula ($r.kod -eq 400) 'Bozuk JSON reddediliyor'
    $r = Istek '/api/gorev-ekle' 'POST' '{"konu": ["test"]}'
    Dogrula ($r.kod -eq 400) 'Beklenmeyen alan türü reddediliyor'
    $r = Istek '/api/gorev-ekle' 'POST' '{"konu":"   "}'
    Dogrula ($r.kod -eq 400) 'Boş konu reddediliyor'
    $r = Istek '/api/gorev-ekle' 'POST' ('{"konu":"' + ('a'*66000) + '"}')
    Dogrula ($r.kod -eq 413) 'Aşırı büyük istek reddediliyor'
    $r = Istek '/api/durum' -Baslik @{ 'Transfer-Encoding'='chunked' }
    Dogrula ($r.kod -eq 400) 'Belirsiz HTTP aktarımı reddediliyor'
    $r = Istek '/api/gorev?id=..%2Fdisari'
    Dogrula ($r.kod -eq 400) 'Görev sorgusunda path traversal reddediliyor'
    $r = Istek '/api/iptal' 'POST' '{"id":"../disari"}'
    Dogrula ($r.kod -eq 400) 'Görev eyleminde path traversal reddediliyor'
    $r = Istek '/api/gorev?id=bulunmayan'
    Dogrula ($r.kod -eq 404) 'Eksik görev 404 döndürüyor'
    $r = Istek '/ortak.ps1'
    Dogrula ($r.kod -eq 404) 'Keyfi kaynak dosyaları sunulmuyor'
    $r = Istek '/api/durum'
    $d = $r.govde | ConvertFrom-Json
    Dogrula ($d.gorevler.Count -eq 0 -and $d.kadro.Count -eq 6 -and $d.saglik -eq 'durdu') 'Boş kuyrukta altı ajan ve durmuş döngü var'
    $konu = 'Türkçe fikir <img src=x onerror=alert(1)>; $(komut) "alıntı"'
    $govde = @{ konu=$konu; alan='eğitim'; proje='örnek-proje' } | ConvertTo-Json -Compress
    $r = Istek '/api/gorev-ekle' 'POST' $govde
    Dogrula ($r.kod -eq 200) 'Gerçek proje-ekle.ps1 üzerinden görev ekleniyor'
    $id = ($r.govde | ConvertFrom-Json).id
    $gorevKok = Join-Path (Join-Path $testKok 'gorevler') $id
    $durumYol = Join-Path $gorevKok 'durum.json'
    $r = Istek ('/api/gorev?id=' + $id)
    $g = $r.govde | ConvertFrom-Json
    Dogrula ($g.baslik -ceq $konu -and $g.belgeler.'gorev.md'.Contains($konu) -and $g.asama -eq 'yeni') 'Türkçe ve komut/HTML karakterleri veri olarak korunuyor'
    $r = Istek '/api/devam' 'POST' (@{id=$id}|ConvertTo-Json)
    Dogrula ($r.kod -eq 409) 'Takılmamış görev devam ettirilemiyor'
    $veri = [IO.File]::ReadAllText($durumYol) | ConvertFrom-Json
    $veri.asama = 'takildi'
    $veri | Add-Member takildi_asama 'poc_plan'
    JsonYaz $durumYol $veri
    $r = Istek '/api/devam' 'POST' (@{id=$id}|ConvertTo-Json)
    Dogrula ($r.kod -eq 200 -and ([IO.File]::ReadAllText($durumYol)|ConvertFrom-Json).asama -eq 'poc_plan') 'Takılan görev gerçek durum.ps1 ile devam ettiriliyor'
    $kalpYol = Join-Path $testKok 'durum/kalp.json'
    $kalp = @{pid=$PID; baslangic=(Get-Process -Id $PID).StartTime.ToString('o'); zaman=(Get-Date).ToString('o'); durum='adım'; gorev=$id; adim='poc_plan'}
    JsonYaz $kalpYol $kalp
    JsonYaz (Join-Path $testKok 'durum/sayaclar.json') @{tarih=(Get-Date).ToString('yyyy-MM-dd');claude=2;codex=3;tamamlanan=1}
    $r = Istek '/api/durum'; $d = $r.govde | ConvertFrom-Json
    Dogrula ($d.aktif_ajan -eq 'planlamaci' -and $d.saglik -eq 'calisiyor' -and $d.aktif_gorev -eq $id -and $d.sayaclar.codex -eq 3) 'Kalpten etkin ajan ve sayaçlar doğru türetiliyor'
    $kalp.durum = 'görev aranıyor'; JsonYaz $kalpYol $kalp
    $r = Istek '/api/durum'; $d = $r.govde | ConvertFrom-Json
    Dogrula ($d.saglik -eq 'bosta' -and -not $d.aktif_ajan -and @($d.kadro|Where-Object durum -eq calisiyor).Count -eq 0) 'Eski görev/adım taşıyan boş kalp aktif sayılmıyor'
    $kalp.zaman = (Get-Date).AddMinutes(-5).ToString('o'); JsonYaz $kalpYol $kalp
    $r = Istek '/api/durum'
    Dogrula (($r.govde|ConvertFrom-Json).saglik -eq 'durdu') 'Eski kalp atışı durmuş sayılıyor'
    $belgeYol = Join-Path $gorevKok 'fikir.md'
    [IO.File]::WriteAllText($belgeYol,('ö'*270000),$utf8Test)
    $r = Istek ('/api/gorev?id=' + $id)
    Dogrula (($r.govde|ConvertFrom-Json).belgeler.'fikir.md' -match 'Belge kısaltıldı') 'Uzun belge yanıtı sınırlanıyor'
    $paylasim = [IO.File]::Open($durumYol,'Open','ReadWrite','ReadWrite')
    try { $r = Istek ('/api/gorev?id=' + $id); Dogrula ($r.kod -eq 200) 'Yazıcı açıkken paylaşımlı durum okunabiliyor' } finally { $paylasim.Dispose() }
    $kilit = [IO.File]::Open((Join-Path $testKok 'durum/gorev.lock'),'OpenOrCreate','ReadWrite','None')
    try { $r = Istek '/api/iptal' 'POST' (@{id=$id}|ConvertTo-Json); Dogrula ($r.kod -eq 409) 'Döngü görev kilidi tutulduğunda eylem çakışmayı bildiriyor' } finally { $kilit.Dispose() }
    $r = Istek '/api/iptal' 'POST' (@{id=$id}|ConvertTo-Json)
    Dogrula ($r.kod -eq 200 -and ([IO.File]::ReadAllText($durumYol)|ConvertFrom-Json).asama -eq 'iptal') 'Gerçek durum.ps1 ile iptal ediliyor'
    Copy-Item -LiteralPath $durumYol -Destination "$durumYol.bak" -Force
    [IO.File]::WriteAllText($durumYol,'{yarim',$utf8Test)
    $r = Istek ('/api/gorev?id=' + $id)
    Dogrula ($r.kod -eq 200 -and ($r.govde|ConvertFrom-Json).asama -eq 'iptal') 'Geçici bozuk JSON durumunda yedek okunuyor'
    $onBaglanti = [Net.Sockets.TcpClient]::new('127.0.0.1',$testPort)
    $r = Istek '/api/durum'
    Dogrula ($r.kod -eq 200) 'Boş tarayıcı ön bağlantısı diğer istekleri engellemiyor'
    $onBaglanti.Dispose(); $onBaglanti = $null
    $eskiPid = $sunucu.Id
    $ikinci = & "$PSHOME/powershell.exe" -NoProfile -NonInteractive -File $betik -Port $testPort 2>&1 | Out-String
    Dogrula ($LASTEXITCODE -eq 0 -and $ikinci -match 'zaten çalışıyor' -and (Get-Content (Join-Path $testKok 'ofis/sunucu.json') -Raw|ConvertFrom-Json).pid -eq $eskiPid) 'Mutex ikinci sunucuyu başlatmıyor'
    $durdurma = & "$PSHOME/powershell.exe" -NoProfile -NonInteractive -File $betik -Durdur 2>&1 | Out-String
    Dogrula ($LASTEXITCODE -eq 0 -and $durdurma -match 'Panel durduruldu') 'Tek komutla panel durduruluyor'
    Dogrula ($sunucu.WaitForExit(5000)) 'Sunucu süreci temiz kapanıyor'
    Dogrula (-not (Test-Path -LiteralPath (Join-Path $testKok 'ofis/sunucu.json'))) 'Kapanışta çalışma kaydı temizleniyor'
    $eskiAnahtar = $anahtar
    $sayfa = PanelBaslat
    $null = $sayfa.govde -match 'const OTURUM = "([a-f0-9]{32})";'
    $script:anahtar = $Matches[1]
    Dogrula ($anahtar -cne $eskiAnahtar) 'Yeniden başlatmada oturum anahtarı değişiyor'
    $r = Istek '/api/durum' -Baslik @{'X-Oturum'=$eskiAnahtar}
    Dogrula ($r.kod -eq 401) 'Önceki oturum yeni sunucuda reddediliyor'
    $r = Istek '/api/kapat' 'POST' '{}'
    Dogrula ($r.kod -eq 200 -and $sunucu.WaitForExit(5000)) 'Panel düğmesinin kapatma API çağrısı çalışıyor'
    Write-Host "Toplam $script:kontrol panel kontrolü geçti. Yalnızca loopback kullanıldı."
} finally {
    if ($onBaglanti) { $onBaglanti.Dispose() }
    if ($sunucu -and -not $sunucu.HasExited) { Stop-Process -Id $sunucu.Id -Force; $sunucu.WaitForExit() }
    $tam = [IO.Path]::GetFullPath($testKok)
    $sinir = [IO.Path]::GetFullPath($testTabani).TrimEnd('\') + '\'
    if ($tam.StartsWith($sinir,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tam)) { Remove-Item -LiteralPath $tam -Recurse -Force }
}
