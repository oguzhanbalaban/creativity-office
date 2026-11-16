# Ek paket, ağ veya gerçek AI çağrısı gerektirmeyen bütünleşme testleri.
$ErrorActionPreference = 'Stop'
$kaynak = Split-Path -Parent $PSScriptRoot
$depo = $kaynak
$testTabani = Join-Path $kaynak '.test-calisma'
$testKok = Join-Path $testTabani ([guid]::NewGuid().ToString('N'))
$ofis = Join-Path $testKok 'yaratici-ofis'
$ana = Join-Path $testKok 'ana-ofis'
$script:kontrol = 0
function Dogrula([bool]$Kosul, [string]$Mesaj) {
    if (-not $Kosul) { throw "BAŞARISIZ: $Mesaj" }
    $script:kontrol++; Write-Host "OK $script:kontrol - $Mesaj"
}
function Hata-Bekle([scriptblock]$Islem, [string]$Mesaj) {
    $oldu = $false
    try { & $Islem | Out-Null } catch { $oldu = $true }
    Dogrula $oldu $Mesaj
}
function AltSurec([string]$Dosya, [string[]]$Ek = @()) {
    $cikti = & "$PSHOME\powershell.exe" -NoProfile -NonInteractive -File $Dosya @Ek 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Alt süreç başarısız: $cikti" }
    return $cikti
}
try {
    foreach ($f in @(Get-ChildItem -LiteralPath $kaynak -Filter '*.ps1' -File -Recurse)) {
        $hata = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$hata)
        Dogrula (@($hata).Count -eq 0) "$($f.Name) sözdizimi"
        $b = [IO.File]::ReadAllBytes($f.FullName)
        Dogrula ($b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) "$($f.Name) UTF-8 BOM"
    }
    New-Item -ItemType Directory -Path $ofis, $ana -Force | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $kaynak -File | Where-Object { $_.Extension -in @('.ps1','.json') -and $_.Name -notlike '*.yerel.json' })) {
        Copy-Item -LiteralPath $f.FullName -Destination $ofis
    }
    Copy-Item -LiteralPath (Join-Path $kaynak 'istemler') -Destination $ofis -Recurse
    $baslatYolu = Join-Path $ofis 'baslat.ps1'
    $baslatMetni = [IO.File]::ReadAllText($baslatYolu).Replace('Local\YaraticiOfisDongusu', ('Local\YaraticiOfisTest' + [guid]::NewGuid().ToString('N')))
    [IO.File]::WriteAllText($baslatYolu, $baslatMetni, (New-Object Text.UTF8Encoding $true))
    $bos = AltSurec (Join-Path $ofis 'baslat.ps1') @('-Konsol','-BosBitir')
    Dogrula ($bos -match 'bitti') 'Boş ofis temiz çıkıyor'
    . (Join-Path $ofis 'ortak.ps1')
    . (Join-Path $ofis 'dongu.ps1')
    Ayarlari-Yukle
    Dogrula (@($Ayar.roller.'karar-verici').Count -eq 2 -and @($Ayar.roller.puanlayici).Count -eq 2) 'Altı rol ortak araç zincirini alıyor'
    foreach ($rol in @('fikirci','elestirmen','planlamaci','maliyet','karar-verici','puanlayici','teslim')) {
        $m = Sablon-Doldur "$rol.md" @{ BELGELER = 'veri'; EK = ''; REVIZYON = 0; SINIR = 3; PROJE = 'test' }
        Dogrula ($m -notmatch '\{[A-Z_]+\}') "$rol istemi dolduruluyor"
    }
    $g = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Test' -Alan 'test' -Proje $depo
    Dogrula ((Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'gorev.md')) -and (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'durum.json'))) 'Görev belgesi ve durum oluşuyor'
    Dogrula ($g.asama -eq 'yeni' -and $g.revizyon -eq 0) 'Görev yeni aşamasında başlıyor'
    Hata-Bekle { Gorev-Oku '../disari' } 'Dizin dışına çıkan görev kimliği reddediliyor'
    Hata-Bekle { Ajan-Cagir -Rol fikirci -Istem test -Klasor $ofis -KayitKlasoru $ofis -Etiket test -Yazabilir } 'Ajanlara yazma yetkisi verilmiyor'
    & {
        function Arac-Uygun($Giris) { return $null }
        function Claude-Calistir { throw 'Sahte süreç başlatma hatası' }
        function Codex-Calistir { return (Sonuc $true 'yedek yanıt' '' $null) }
        $r = Ajan-Cagir -Rol fikirci -Istem test -Klasor $ofis -KayitKlasoru (Join-Path $ofis 'calisma/yedek-test') -Etiket test
        Dogrula ($r.basarili -and $r.arac -eq 'codex' -and $r.metin -eq 'yedek yanıt') 'Süreç hatasında yedek araç zinciri çalışıyor'
    }
    $sayac = Sayac-Oku
    $sayac.claude = [int]$Ayar.gunluk_sinir.claude
    Json-Yaz $sayac (Join-Path $YolDurum 'sayaclar.json')
    Dogrula ((Arac-Uygun $Ayar.roller.fikirci[0]) -match 'günlük sınır') 'Ofise özel günlük araç sınırı uygulanıyor'

    # İsteğe bağlı köprü sözleşmesinin bağımsız test düzeneği.
    Copy-Item -LiteralPath (Join-Path $kaynak 'testler/fixtures/gorev-ekle.ps1') -Destination $ana
    $Ayar.ana_ofis_yolu = $ana
    $script:karar = 'ONAYLA'; $script:puan = '8'; $script:roller = @(); $script:istemler = @()
    function Ajan-Cagir($Rol, $Istem, $Klasor, $KayitKlasoru, $Etiket) {
        $script:roller += $Rol; $script:istemler += $Istem
        New-Item -ItemType Directory -Path $KayitKlasoru -Force | Out-Null
        $m = "Test raporu: $Rol"
        if ($Rol -eq 'karar-verici') { $m = "KARAR: $script:karar`nSomut revizyon gerekçesi" }
        if ($Rol -eq 'teslim') { $m = '{"baslik":"Test POC","aciklama":"Küçük test POC","kabul":["Yerel test geçer"]}' }
        if ($Rol -eq 'puanlayici') { $m = "PUAN: $script:puan`nKanıta dayalı rapor" }
        return [pscustomobject]@{ basarili = $true; metin = $m; hata = '' }
    }
    foreach ($beklenen in @('fikir','elestiri','poc_plan','maliyet','karar','teslim')) {
        Yaratici-Adim $g
        Gorev-Kaydet $g
        Dogrula ($g.asama -eq $beklenen) "Aşama sırası: $beklenen"
    }
    Yaratici-Adim $g; Gorev-Kaydet $g
    Dogrula ($g.asama -eq 'bekleme' -and $g.ana_gorev_id) 'ONAYLA köprü sözleşmesi üzerinden teslim ediyor'
    Dogrula ($script:Kok -eq $ofis) 'Ana ofis çağrısı yaratıcı ofis kapsamını bozmuyor'
    $gk = Gorev-Klasoru $g.id
    $paket = Json-Oku (Join-Path $gk 'teslim.json')
    Dogrula ($paket.proje -eq $depo -and $paket.aciklama -match 'maliyet.md') 'Teslim hedefi sabit ve tüm onaylı belgeleri içeriyor'
    $ilk = $g.ana_gorev_id
    $tekrar = Gorevi-Gonder $paket $ana (Join-Path $gk 'teslim-kaydi.json')
    Dogrula ($ilk -eq $tekrar.id -and @(Get-ChildItem -LiteralPath (Join-Path $ana 'gorevler') -Directory).Count -eq 1) 'Teslim tekrarında ikinci ana ofis görevi oluşmuyor'
    $anaDurum = Join-Path (Join-Path (Join-Path $ana 'gorevler') $ilk) 'durum.json'
    $once = (Get-FileHash -LiteralPath $anaDurum).Hash
    Yaratici-Adim $g
    Dogrula ($g.asama -eq 'bekleme' -and [datetime]$g.sonraki_deneme -gt (Get-Date)) 'Ana ofis çalışırken polling erteleniyor'
    Dogrula ((Get-FileHash -LiteralPath $anaDurum).Hash -eq $once) 'İzleme ana ofis durumunu değiştirmiyor'
    $ag = Json-Oku $anaDurum; $ag.asama = 'takildi'; Json-Yaz $ag $anaDurum
    Yaratici-Adim $g; Gorev-Kaydet $g
    Dogrula ($g.asama -eq 'takildi' -and $g.takildi_asama -eq 'bekleme') 'Ana ofisin takıldı durumu algılanıyor'
    $g = & (Join-Path $ofis 'durum.ps1') -Devam $g.id
    Dogrula ($g.asama -eq 'bekleme') 'Devam kaldığı aşamayı koruyor'
    $ag.asama = 'tamam'; Ayarla $ag 'commit' 'test-commit'; Json-Yaz $ag $anaDurum
    $tur = Join-Path (Split-Path -Parent $anaDurum) 'tur1'
    New-Item -ItemType Directory -Path $tur -Force | Out-Null
    Metin-Yaz (Join-Path $tur 'degisiklik.diff') '+test POC çıktısı'
    Metin-Yaz (Join-Path $tur 'denetim.md') 'Denetim: geçti'
    Metin-Yaz (Join-Path $tur 'gelistirici-ozet.md') 'Uygulama özeti'
    Metin-Yaz (Join-Path $tur 'inceleme-mimar.md') 'Mimari inceleme geçti'
    Yaratici-Adim $g
    Dogrula ($g.asama -eq 'puanlama') 'Ana ofisin tamam durumu puanlamaya geçiyor'
    $cikti = Ciktiyi-Oku $ilk $ana
    Dogrula ($cikti -match 'test-commit' -and $cikti -match 'test POC çıktısı' -and $cikti -match 'Denetim: geçti') 'Commit, diff ve denetim raporu toplanıyor'
    Dogrula ($cikti -match 'Uygulama özeti' -and $cikti -match 'Mimari inceleme geçti') 'Gerçek ana ofis dosya adlarıyla geliştirici ve ek inceleme raporları toplanıyor'
    $script:puan = '11'
    Hata-Bekle { Yaratici-Adim $g } '1-10 dışındaki puan kabul edilmiyor'
    Dogrula ($g.asama -eq 'puanlama') 'Hatalı puan görevi kapatmıyor'
    $script:puan = '8'; Yaratici-Adim $g; Gorev-Kaydet $g
    Dogrula ($g.asama -eq 'tamam' -and $g.puan -eq 8 -and (Test-Path -LiteralPath (Join-Path $gk 'sonuc.md'))) 'Geçerli puan ve sonuç raporu kaydediliyor'
    Dogrula ((Metin-Oku (Join-Path $gk 'puanlama.md')) -match 'PUAN: 8') 'Puanlama belgesi oluşuyor'

    $rev = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Revizyon testi'
    $rev.asama = 'karar'; $script:karar = 'REVIZE'
    foreach ($sayi in @(1,2,3)) {
        Yaratici-Adim $rev
        Dogrula ($rev.asama -eq 'elestiri' -and $rev.revizyon -eq $sayi) "Revizyon $sayi eleştiriye dönüyor"
        foreach ($asama in @('poc_plan','maliyet','karar')) { Yaratici-Adim $rev; Dogrula ($rev.asama -eq $asama) "Revizyon $sayi aşaması: $asama" }
    }
    Yaratici-Adim $rev
    Dogrula ($rev.asama -eq 'reddedildi' -and $rev.revizyon -eq 3) 'Dördüncü revizyon isteği reddediliyor'
    Dogrula (@($rev.geri_bildirimler).Count -eq 3 -and ($script:istemler[-1] -match 'Revizyon hakkı bitti')) 'Revizyon geçmişi birikiyor ve son karar zorlanıyor'
    $red = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Red testi'
    $red.asama = 'karar'; $script:karar = 'REDDET'; Yaratici-Adim $red
    Dogrula ($red.asama -eq 'reddedildi') 'REDDET doğrudan kapatıyor'
    $hatali = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Hata testi'
    $hatali.asama = 'karar'; $script:karar = 'BELIRSIZ'
    Hata-Bekle { Yaratici-Adim $hatali } 'Geçersiz karar ilerlemiyor'
    foreach ($i in @(1,2,3)) { Adim-Basarisiz $hatali 'test hatası' }
    Dogrula ($hatali.asama -eq 'takildi' -and $hatali.takildi_asama -eq 'karar') 'Hata deneme sınırı takıldı ile duruyor'

    $belirsiz = [pscustomobject]@{ baslik = 'Belirsiz'; aciklama = 'test'; proje = $depo; kabul = @('test'); anahtar = ([guid]::NewGuid().ToString('N')) }
    $kayitYolu = Join-Path $gk 'belirsiz.json'
    Json-Yaz ([pscustomobject]@{ anahtar = $belirsiz.anahtar; ana_ofis = $ana; denendi = $true }) $kayitYolu
    Hata-Bekle { Gorevi-Gonder $belirsiz $ana $kayitYolu } 'Belirsiz teslim otomatik yinelenmiyor'
    Hata-Bekle { Gorevi-Izle $ilk (Join-Path $testKok 'yok') } 'Yanlış ana ofis yolu açık hata üretiyor'
    Gorev-Kaydet $hatali
    $iptal = & (Join-Path $ofis 'durum.ps1') -Iptal $hatali.id
    Dogrula ($iptal.asama -eq 'iptal') 'İptal görevi kapatıyor'
    Gorev-Kaydet $rev; Gorev-Kaydet $red
    $donguGorevi = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Döngü testi'
    function Kalpli-Bekle($Saniye, $Mesaj) { Kalp $Mesaj }
    $son = Yaratici-Dongusu -AdimSiniri 1
    $donguGorevi = Gorev-Oku $donguGorevi.id
    Dogrula ($son -eq 'sinir' -and $donguGorevi.asama -eq 'fikir') 'Döngü adım sınırını ve kalıcı aşama geçişini uyguluyor'
    $donguGorevi.sonraki_deneme = (Get-Date).AddHours(1).ToString('o'); Gorev-Kaydet $donguGorevi
    Dogrula ((Yaratici-Dongusu -BosBitir) -eq 'bitti') 'Gelecekteki görevler BosBitir ile beklenmiyor'
    Metin-Yaz (Join-Path $ofis 'DURDUR') 'test'
    Dogrula ((Yaratici-Dongusu) -eq 'durduruldu') 'DURDUR dosyası bağımsız döngüyü durduruyor'
    # Tam bağımsız yerel teslim, bekleme, çıktı ve puanlama yolu.
    $Ayar.ana_ofis_yolu = ''
    $yerel = & (Join-Path $ofis 'proje-ekle.ps1') -Konu 'Bağımsız POC' -Proje $depo
    $yerel.asama = 'teslim'
    Yaratici-Adim $yerel; Gorev-Kaydet $yerel
    Dogrula ($yerel.asama -eq 'bekleme' -and $yerel.teslim_turu -eq 'yerel') 'Köprü ayarı olmadan yerel teslim çalışıyor'
    Dogrula (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $yerel.id) 'teslim.json')) 'Onaylı yerel teslim paketi oluşuyor'
    Yaratici-Adim $yerel; Gorev-Kaydet $yerel
    Dogrula ($yerel.asama -eq 'bekleme' -and [datetime]$yerel.sonraki_deneme -gt (Get-Date)) 'Yerel teslim uygulama çıktısını bekliyor'
    # DURDUR dosyası yalnızca döngüyü etkiler; yönetim komutlarını engellemez.
    $kanit = Join-Path $testKok 'kanit.md'; Metin-Yaz $kanit 'Uygulama diff ve test raporu'
    $bosKanit = Join-Path $testKok 'bos.md'; Metin-Yaz $bosKanit ''
    Hata-Bekle { & (Join-Path $ofis 'sonuc-ekle.ps1') -Id $yerel.id -Dosya $bosKanit } 'Boş uygulama çıktısı reddediliyor'
    Hata-Bekle { & (Join-Path $ofis 'sonuc-ekle.ps1') -Id $ilk -Dosya $kanit } 'Başka görev türüne yerel çıktı eklenmiyor'
    $yerel = & (Join-Path $ofis 'sonuc-ekle.ps1') -Id $yerel.id -Dosya $kanit
    Dogrula ($yerel.asama -eq 'puanlama' -and -not $yerel.sonraki_deneme) 'Yerel çıktı komutu puanlamayı hazır hale getiriyor'
    $script:puan = '8'; Yaratici-Adim $yerel; Gorev-Kaydet $yerel
    Dogrula ($yerel.asama -eq 'tamam' -and $yerel.puan -eq 8) 'Bağımsız akış puanla tamamlanıyor'
    Dogrula ((Metin-Oku (Join-Path (Gorev-Klasoru $yerel.id) 'ana-ofis-ciktisi.md')) -match 'Uygulama diff') 'Yerel çıktı puanlayıcıya aktarılıyor'
    Hata-Bekle { & (Join-Path $ofis 'sonuc-ekle.ps1') -Id $yerel.id -Dosya $kanit } 'Tamamlanmış göreve yeniden çıktı eklenmiyor'
    $Ayar.revizyon_siniri = 4; Json-Yaz $Ayar (Join-Path $ofis 'ayarlar.json')
    Hata-Bekle { Ayarlari-Yukle } 'Üçten büyük revizyon ayarı reddediliyor'
    Write-Host "Toplam $script:kontrol kontrol geçti. Gerçek AI/ağ çağrısı yapılmadı."
} finally {
    $tam = [IO.Path]::GetFullPath($testKok)
    $sinir = [IO.Path]::GetFullPath($testTabani).TrimEnd('\') + '\'
    if ($tam.StartsWith($sinir, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tam)) { Remove-Item -LiteralPath $tam -Recurse -Force }
}
