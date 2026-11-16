# Yalnızca fonksiyon tanımları: ortak.ps1 çağıran tarafından yüklenir.
function Ana-Ofis-Koku([string]$Yol) {
    if (-not $Yol) { throw 'ana_ofis_yolu yapılandırılmamış.' }
    if (-not [IO.Path]::IsPathRooted($Yol)) { $Yol = Join-Path $Kok $Yol }
    if (-not (Test-Path -LiteralPath (Join-Path $Yol 'gorev-ekle.ps1') -PathType Leaf)) { throw "Ana ofisin gorev-ekle.ps1 dosyası bulunamadı: $Yol" }
    return (Resolve-Path -LiteralPath $Yol).Path
}
function Ana-Gorev-Bul([string]$AnaKok, [string]$Anahtar) {
    $bulunan = @()
    $gorevler = Join-Path $AnaKok 'gorevler'
    if (Test-Path -LiteralPath $gorevler) {
        foreach ($d in @(Get-ChildItem -LiteralPath $gorevler -Directory)) {
            if ((Metin-Oku (Join-Path $d.FullName 'gorev.md')).Contains("[yaratici-ofis:$Anahtar]")) {
                $g = Json-Oku (Join-Path $d.FullName 'durum.json')
                if ($g) { $bulunan += $g }
            }
        }
    }
    if ($bulunan.Count -gt 1) { throw 'Aynı teslim anahtarıyla birden fazla ana ofis görevi var; elle uzlaştırın.' }
    if ($bulunan.Count -eq 1) { return $bulunan[0] }
    return $null
}
function Teslim-Dogrula($PocPlan) {
    foreach ($ad in @('baslik','aciklama','proje','anahtar')) {
        if (-not ([string]$PocPlan.$ad).Trim()) { throw "Teslim alanı eksik: $ad" }
    }
    if ($PocPlan.anahtar -notmatch '^[a-f0-9]{32}$') { throw 'Geçersiz teslim anahtarı.' }
    if (@($PocPlan.kabul).Count -eq 0) { throw 'En az bir kabul ölçütü gerekli.' }
    foreach ($olcut in @($PocPlan.kabul)) {
        if ($olcut -isnot [string] -or -not $olcut.Trim()) { throw 'Kabul ölçütleri boş olmayan metinler olmalıdır.' }
    }
}
function Gorevi-Gonder($PocPlan, [string]$AnaOfisYolu, [string]$KayitYolu) {
    Teslim-Dogrula $PocPlan
    $anaKok = Ana-Ofis-Koku $AnaOfisYolu
    if (-not $KayitYolu) { $KayitYolu = Join-Path $YolDurum "teslim-$($PocPlan.anahtar).json" }
    $kayit = Json-Oku $KayitYolu
    if ($kayit -and ($kayit.anahtar -ne $PocPlan.anahtar -or $kayit.ana_ofis -ne $anaKok)) { throw 'Teslim kaydı başka bir ana ofise/anahtara ait.' }
    $bulunan = Ana-Gorev-Bul $anaKok $PocPlan.anahtar
    if ($bulunan) { return $bulunan }
    if ($kayit -and $kayit.denendi) {
        throw 'Önceki teslimin sonucu belirsiz. Ana ofis kayıtlarını inceleyin; yinelenen görev oluşturmamak için otomatik yeniden gönderilmedi.'
    }
    $kayit = [pscustomobject]@{ anahtar = $PocPlan.anahtar; ana_ofis = $anaKok; denendi = $true; zaman = (Simdi); gorev_id = '' }
    Json-Yaz $kayit $KayitYolu
    $parametreler = @{
        Proje = [string]$PocPlan.proje
        # Ana ofis slug'ı 40 karakterde keser; benzersiz işaret başta kalmalı.
        Baslik = ('[YO-{0}] {1}' -f $PocPlan.anahtar.Substring(0,8), $PocPlan.baslik)
        Aciklama = ($PocPlan.aciklama + "`n`n[yaratici-ofis:$($PocPlan.anahtar)]")
        Kabul = [string[]]@($PocPlan.kabul)
    }
    # Ayrı script kapsamı: ana ofisin ortak.ps1 değişkenleri bu ofisi değiştirmez.
    $hata = ''
    try { & (Join-Path $anaKok 'gorev-ekle.ps1') @parametreler | Out-Null }
    catch { $hata = $_.Exception.Message }
    $bulunan = Ana-Gorev-Bul $anaKok $PocPlan.anahtar
    if (-not $bulunan) { throw "Ana ofise teslim doğrulanamadı. $hata" }
    $kayit.gorev_id = $bulunan.id
    Json-Yaz $kayit $KayitYolu
    return $bulunan
}
function Gorevi-Izle([string]$GorevId, [string]$AnaOfisYolu) {
    Kimlik-Dogrula $GorevId
    $anaKok = Ana-Ofis-Koku $AnaOfisYolu
    $yol = Join-Path (Join-Path (Join-Path $anaKok 'gorevler') $GorevId) 'durum.json'
    $g = Json-Oku $yol
    if (-not $g) { throw "Ana ofis görev durumu okunamadı: $yol" }
    if ($g.asama -notin @('yeni','plan','gelistirme','kontrol','denetim','kabul','tamamla','tamam','takildi','iptal','bekliyor_kullanici')) { throw "Bilinmeyen ana ofis aşaması: $($g.asama)" }
    return $g
}
function Ciktiyi-Oku([string]$GorevId, [string]$AnaOfisYolu) {
    $g = Gorevi-Izle $GorevId $AnaOfisYolu
    if ($g.asama -ne 'tamam') { throw 'Puanlama için ana ofis görevi tamamlanmış olmalıdır.' }
    $anaKok = Ana-Ofis-Koku $AnaOfisYolu
    $gk = Join-Path (Join-Path $anaKok 'gorevler') $GorevId
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# Ana ofis çıktısı: $GorevId`nCommit: $($g.commit)`nDal: $($g.dal)`nÇalışma klasörü: $($g.calisma_klasoru)")
    [void]$sb.AppendLine(($g | ConvertTo-Json -Depth 10))
    $dosyalar = @(Get-ChildItem -LiteralPath $gk -File -Recurse | Where-Object {
        $_.Name -in @('gorev.md','plan.md','gelistirici-ozet.md','kontrol.md','denetim.md','kabul.md','degisiklik.diff') -or $_.Name -like 'inceleme-*.md'
    } | Sort-Object @{ Expression = {
        # Büyük eski turlar çıktı sınırını doldurmadan son turun kanıtlarını oku.
        $goreli = $_.FullName.Substring($gk.Length + 1)
        if ($goreli -match '^tur(\d+)[\\/]') { return [int]$Matches[1] }
        return 0
    }; Descending = $true }, Name)
    $kalan = 160000
    foreach ($f in $dosyalar) {
        if ($kalan -le 0) { [void]$sb.AppendLine('[Toplam çıktı sınırı nedeniyle kesildi.]'); break }
        $metin = Metin-Oku $f.FullName
        $sinir = [Math]::Min(40000, $kalan)
        if ($metin.Length -gt $sinir) { $metin = $metin.Substring(0,$sinir) + "`n[Dosya kesildi.]" }
        $kalan -= $metin.Length
        [void]$sb.AppendLine("`n## $($f.FullName.Substring($gk.Length + 1))`n$metin")
    }
    if (-not @($dosyalar | Where-Object { $_.Name -eq 'degisiklik.diff' }).Count) { [void]$sb.AppendLine('UYARI: Kayıtlı diff bulunamadı; uygulama kanıtı eksik.') }
    return $sb.ToString()
}
