# ortak.ps1 yüklendikten sonra dot-source edilir; gerçek ajan çağrısı yalnızca döngüde yapılır.
. (Join-Path $PSScriptRoot 'kopru.ps1')
$script:AktifAsamalar = @('yeni','fikir','elestiri','poc_plan','maliyet','karar','teslim','bekleme','puanlama')
function Asama-Gec($G, [string]$Yeni, [string]$Neden = '') {
    $olay = [pscustomobject]@{ zaman = (Simdi); onceki = $G.asama; yeni = $Yeni; revizyon = $G.revizyon; neden = $Neden }
    $G.gecmis = @($G.gecmis) + $olay
    $G.asama = $Yeni; $G.deneme = 0; $G.sonraki_deneme = $null; $G.son_hata = ''
    Gunluk "$($G.id): -> $Yeni ($Neden)"
}
function Takildi($G, [string]$Neden) {
    Ayarla $G 'takildi_asama' $G.asama
    Asama-Gec $G 'takildi' $Neden
    $G.son_hata = $Neden
    Bildir -Baslik "Yaratıcı ofis takıldı: $($G.baslik)" -Metin $Neden -Anahtar "takildi-$($G.id)"
}
function Adim-Basarisiz($G, [string]$Hata) {
    $G.deneme = [int]$G.deneme + 1
    $G.son_hata = $Hata
    Gunluk "$($G.id) / $($G.asama): $Hata" 'HATA'
    if ($G.deneme -ge [int]$Ayar.dongu.max_adim_denemesi) { Takildi $G $Hata }
    else { $G.sonraki_deneme = (Get-Date).AddMinutes([int]$Ayar.dongu.hata_bekleme_dk * $G.deneme).ToString('o') }
}
function Belgeleri-Oku($G) {
    $gk = Gorev-Klasoru $G.id
    $b = New-Object Text.StringBuilder
    foreach ($ad in @('gorev.md','fikir.md','elestiri.md','poc-plan.md','maliyet.md','karar.md')) {
        $m = Metin-Oku (Join-Path $gk $ad)
        if ($m) { [void]$b.AppendLine("## $ad`n$m`n") }
    }
    [void]$b.AppendLine("## Önceki revizyon geri bildirimleri`n$(@($G.geri_bildirimler) -join "`n`n")")
    return $b.ToString()
}
function Rol-Calistir($G, [string]$Rol, [string]$Dosya, [string]$Ek = '') {
    $gk = Gorev-Klasoru $G.id
    $degerler = @{
        BELGELER = (Belgeleri-Oku $G); EK = $Ek; REVIZYON = $G.revizyon
        SINIR = $Ayar.revizyon_siniri; PROJE = $G.proje
    }
    $istem = Sablon-Doldur "$Rol.md" $degerler
    $kayit = Join-Path $gk ('kayitlar/revizyon-{0}/{1}-deneme-{2}' -f $G.revizyon, $Rol, ($G.deneme + 1))
    $r = Ajan-Cagir -Rol $Rol -Istem $istem -Klasor $gk -KayitKlasoru $kayit -Etiket $Rol
    if (-not $r.basarili -or -not ([string]$r.metin).Trim()) { throw "${Rol}: $($r.hata) (boş veya başarısız çıktı)" }
    Metin-Yaz (Join-Path $kayit 'yanit.md') $r.metin
    if ($Dosya) { Metin-Yaz (Join-Path $gk $Dosya) $r.metin }
    return [string]$r.metin
}
function Rapor-Yaz($G) {
    $gk = Gorev-Klasoru $G.id
    $metin = "# $($G.baslik)`n`nDurum: $($G.asama)`nRevizyon: $($G.revizyon)/$($Ayar.revizyon_siniri)`nAna görev: $($G.ana_gorev_id)`nPuan: $($G.puan)`n`n"
    $metin += Belgeleri-Oku $G
    $metin += "`n## Puanlama`n" + (Metin-Oku (Join-Path $gk 'puanlama.md'))
    Metin-Yaz (Join-Path $gk 'sonuc.md') $metin
    Metin-Yaz (Join-Path $YolRapor "$($G.id).md") $metin
    Metin-Yaz (Join-Path $YolRapor 'son-rapor.md') $metin
}
function Yaratici-Adim($G) {
    $script:AktifGorev = $G.id; $script:AktifAdim = $G.asama
    Kalp 'adım'
    $gk = Gorev-Klasoru $G.id
    switch ($G.asama) {
        'yeni' { Asama-Gec $G 'fikir' 'Görev hazır' }
        'fikir' { $null = Rol-Calistir $G 'fikirci' 'fikir.md'; Asama-Gec $G 'elestiri' }
        'elestiri' { $null = Rol-Calistir $G 'elestirmen' 'elestiri.md'; Asama-Gec $G 'poc_plan' }
        'poc_plan' { $null = Rol-Calistir $G 'planlamaci' 'poc-plan.md'; Asama-Gec $G 'maliyet' }
        'maliyet' { $null = Rol-Calistir $G 'maliyet' 'maliyet.md'; Asama-Gec $G 'karar' }
        'karar' {
            $ek = ''
            if ([int]$G.revizyon -ge [int]$Ayar.revizyon_siniri) { $ek = 'Revizyon hakkı bitti. Yalnızca ONAYLA veya REDDET seç. REVIZE gelirse sistem reddeder.' }
            $metin = Rol-Calistir $G 'karar-verici' 'karar.md' $ek
            $kararlar = [regex]::Matches($metin, '(?m)^KARAR:\s*(ONAYLA|REVIZE|REDDET)\s*$')
            if ($kararlar.Count -ne 1) { throw 'Karar çıktısı tam bir KARAR: ONAYLA/REVIZE/REDDET satırı içermelidir.' }
            $karar = $kararlar[0].Groups[1].Value
            if ($karar -eq 'ONAYLA') { Asama-Gec $G 'teslim' 'POC onaylandı' }
            elseif ($karar -eq 'REVIZE' -and [int]$G.revizyon -lt [int]$Ayar.revizyon_siniri) {
                $G.geri_bildirimler = @($G.geri_bildirimler) + "Revizyon $([int]$G.revizyon + 1):`n$metin"
                $G.revizyon = [int]$G.revizyon + 1
                Asama-Gec $G 'elestiri' 'Revizyon istendi'
            } else {
                $neden = 'Karar verici reddetti'
                if ($karar -eq 'REVIZE') { $neden = 'Revizyon sınırında yeniden revizyon istendi; otomatik red' }
                Asama-Gec $G 'reddedildi' $neden
                Rapor-Yaz $G
                Bildir -Baslik 'Yaratıcı ofis: POC reddedildi' -Metin "$($G.baslik): $neden" -Anahtar "red-$($G.id)"
            }
        }
        'teslim' {
            if (-not $G.proje) { throw 'Hedef proje eksik. proje-ekle.ps1 -Proje veya varsayilan_proje ayarı gerekli; görev durumundaki proje alanını düzeltip devam edin.' }
            $teslimYolu = Join-Path $gk 'teslim.json'
            $paket = Json-Oku $teslimYolu
            if (-not $paket) {
                $metin = Rol-Calistir $G 'teslim' 'teslim.md'
                try { $paket = $metin | ConvertFrom-Json } catch { throw 'Teslim ajanı yalnızca geçerli JSON döndürmelidir.' }
                Ayarla $paket 'proje' $G.proje
                Ayarla $paket 'anahtar' $G.teslim_anahtari
                # Ana ofise maliyet ve karar dahil tüm onaylı bağlamı taşı.
                Ayarla $paket 'aciklama' (([string]$paket.aciklama) + "`n`n" + (Belgeleri-Oku $G))
                Teslim-Dogrula $paket
                Json-Yaz $paket $teslimYolu
            }
            # Yapılandırılmış köprü yoksa onaylı paket bu depoda bekler.
            if (-not ([string]$Ayar.ana_ofis_yolu).Trim()) {
                Ayarla $G 'teslim_turu' 'yerel'
                Asama-Gec $G 'bekleme' 'Yerel teslim.json hazır; sonuc-ekle.ps1 ile uygulama çıktısı bekleniyor'
                return
            }
            Ayarla $G 'teslim_turu' 'kopru'
            $ana = Gorevi-Gonder $paket $Ayar.ana_ofis_yolu (Join-Path $gk 'teslim-kaydi.json')
            Ayarla $G 'ana_gorev_id' $ana.id
            # Gönderimden sonra ayar değişse de eski görevi aynı ofiste izler.
            Ayarla $G 'ana_ofis' (Ana-Ofis-Koku $Ayar.ana_ofis_yolu)
            Asama-Gec $G 'bekleme' 'Ana ofise teslim edildi'
        }
        'bekleme' {
            if ($G.teslim_turu -eq 'yerel') {
                $G.sonraki_deneme = (Get-Date).AddSeconds([int]$Ayar.dongu.izleme_araligi_sn).ToString('o')
                return
            }
            $ana = Gorevi-Izle $G.ana_gorev_id $G.ana_ofis
            Ayarla $G 'ana_asama' $ana.asama
            if ($ana.asama -eq 'tamam') { Asama-Gec $G 'puanlama' }
            elseif ($ana.asama -in @('takildi','iptal')) { Takildi $G "Ana ofis görevi $($ana.asama): $($ana.son_hata)" }
            else {
                $G.deneme = 0; $G.son_hata = ''
                $G.sonraki_deneme = (Get-Date).AddSeconds([int]$Ayar.dongu.izleme_araligi_sn).ToString('o')
            }
        }
        'puanlama' {
            if ($G.teslim_turu -eq 'yerel') {
                $cikti = Metin-Oku (Join-Path $gk 'uygulama-ciktisi.md')
                if (-not $cikti.Trim()) { throw 'Yerel uygulama çıktısı bulunamadı; sonuc-ekle.ps1 kullanın.' }
            } else { $cikti = Ciktiyi-Oku $G.ana_gorev_id $G.ana_ofis }
            Metin-Yaz (Join-Path $gk 'ana-ofis-ciktisi.md') $cikti
            $metin = Rol-Calistir $G 'puanlayici' '' $cikti
            $puanlar = [regex]::Matches($metin, '(?m)^PUAN:\s*(10|[1-9])\s*$')
            if ($puanlar.Count -ne 1) { throw 'Puanlama tam bir PUAN: 1-10 satırı içermelidir.' }
            Ayarla $G 'puan' ([int]$puanlar[0].Groups[1].Value)
            Metin-Yaz (Join-Path $gk 'puanlama.md') $metin
            Asama-Gec $G 'tamam' 'Ana ofis çıktısı puanlandı'
            Rapor-Yaz $G
            Sayac-Artir 'tamamlanan'
            Bildir -Baslik 'Yaratıcı ofis: POC tamamlandı' -Metin "$($G.baslik): $($G.puan)/10" -Anahtar "tamam-$($G.id)"
        }
        default { throw "Bilinmeyen yaratıcı ofis aşaması: $($G.asama)" }
    }
}
function Calisma-Saati {
    $parcalar = ([string]$Ayar.dongu.calisma_saatleri).Split('-')
    $bas = [TimeSpan]::Parse($parcalar[0]).TotalMinutes
    $son = 1440
    if ($parcalar[1] -ne '24:00') { $son = [TimeSpan]::Parse($parcalar[1]).TotalMinutes }
    $simdi = (Get-Date).TimeOfDay.TotalMinutes
    if ($bas -le $son) { return ($simdi -ge $bas -and $simdi -lt $son) }
    return ($simdi -ge $bas -or $simdi -lt $son)
}
function Yaratici-Dongusu([int]$AdimSiniri = 0, [switch]$BosBitir) {
    $adim = 0
    while (-not (Test-Path -LiteralPath (Join-Path $Kok 'DURDUR'))) {
        Kalp 'görev aranıyor'
        $hazir = @()
        if (Calisma-Saati) {
            $hazir = @(Gorevleri-Listele | Where-Object {
                $_.asama -in $AktifAsamalar -and (-not $_.sonraki_deneme -or [datetime]$_.sonraki_deneme -le (Get-Date))
            } | Sort-Object oncelik, guncelleme, id)
        }
        if (-not $hazir.Count) {
            if ($BosBitir) { return 'bitti' }
            Kalpli-Bekle ([int]$Ayar.dongu.bos_bekleme_sn)
            continue
        }
        $kilit = Ofis-Kilidi 'gorev'
        try {
            # Yönetim komutu seçimden sonra görev durumunu değiştirmiş olabilir.
            $g = Gorev-Oku $hazir[0].id
            if ($g.asama -notin $AktifAsamalar) { continue }
            try { Yaratici-Adim $g }
            catch { Adim-Basarisiz $g $_.Exception.Message }
            Gorev-Kaydet $g
        } finally { $kilit.Dispose() }
        $adim++
        if ($AdimSiniri -gt 0 -and $adim -ge $AdimSiniri) { return 'sinir' }
        Kalpli-Bekle ([int]$Ayar.dongu.adim_arasi_sn) 'adımlar arası'
    }
    return 'durduruldu'
}
