# Creativity Office ortak işlevleri; başka bir depodan import yapılmaz.
$ErrorActionPreference = 'Stop'
$script:Kok = $PSScriptRoot
$script:Utf8 = New-Object Text.UTF8Encoding $false
$script:YolGorev = Join-Path $Kok 'gorevler'
$script:YolDurum = Join-Path $Kok 'durum'
$script:YolGunluk = Join-Path $Kok 'gunluk'
$script:YolRapor = Join-Path $Kok 'raporlar'
$script:YolCalisma = Join-Path $Kok 'calisma'
$script:YolIstem = Join-Path $Kok 'istemler'
foreach ($d in @($YolGorev, $YolDurum, $YolGunluk, $YolRapor, $YolCalisma)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
}
if (-not (Test-Path variable:script:Konsol)) { $script:Konsol = $false }
$script:AktifGorev = ''
$script:AktifAdim = ''
function Yapilandirma-Yolu([string]$Yol, [switch]$Yaz) {
    if (-not $Yol) { return $Yol }
    foreach ($ad in @('ayarlar','kadro')) {
        if ([IO.Path]::GetFullPath($Yol) -ieq (Join-Path $Kok "$ad.json")) {
            $yerel = Join-Path $Kok "$ad.yerel.json"
            if ($Yaz -or (Test-Path -LiteralPath $yerel) -or (Test-Path -LiteralPath "$yerel.bak")) { return $yerel }
        }
    }
    return $Yol
}

function Metin-Oku([string]$Yol) {
    if ($Yol -and (Test-Path -LiteralPath $Yol)) { return [IO.File]::ReadAllText($Yol, $Utf8) }
    return ''
}

function Metin-Yaz([string]$Yol, [string]$Metin) {
    $tmp = "$Yol.tmp"
    [IO.File]::WriteAllText($tmp, $Metin, $Utf8)
    if (Test-Path -LiteralPath $Yol) { [IO.File]::Replace($tmp, $Yol, "$Yol.bak") }
    else { [IO.File]::Move($tmp, $Yol) }
}

function Json-Oku([string]$Yol) {
    $Yol = Yapilandirma-Yolu $Yol
    foreach ($aday in @($Yol, "$Yol.bak")) {
        $t = Metin-Oku $aday
        if ($t.Trim()) { try { return ($t | ConvertFrom-Json) } catch {} }
    }
    return $null
}

function Json-Yaz($Nesne, [string]$Yol) { Metin-Yaz (Yapilandirma-Yolu $Yol -Yaz) ($Nesne | ConvertTo-Json -Depth 10) }

function Ayarla($Nesne, [string]$Ad, $Deger) {
    if ($Nesne.PSObject.Properties[$Ad]) { $Nesne.$Ad = $Deger }
    else { $Nesne | Add-Member -NotePropertyName $Ad -NotePropertyValue $Deger }
}

function Kisalt([string]$Metin, [int]$Uzunluk = 300) {
    if (-not $Metin) { return '' }
    $m = ($Metin -replace '\s+', ' ').Trim()
    if ($m.Length -le $Uzunluk) { return $m }
    return $m.Substring(0, $Uzunluk) + '...'
}

function Son-Satirlar([string]$Metin, [int]$Adet = 10) {
    if (-not $Metin) { return '' }
    $s = $Metin -split "`r?`n" | Where-Object { $_.Trim() }
    return (@($s) | Select-Object -Last $Adet) -join "`n"
}

function Simdi { (Get-Date).ToString('o') }

function Slug([string]$s) {
    $t = $s.Replace('İ', 'i').Replace('I', 'i').ToLowerInvariant()
    foreach ($c in @(@('ç', 'c'), @('ğ', 'g'), @('ı', 'i'), @('ö', 'o'), @('ş', 's'), @('ü', 'u'), @('â', 'a'), @('î', 'i'), @('û', 'u'))) { $t = $t.Replace($c[0], $c[1]) }
    $t = ($t -replace '[^a-z0-9]+', '-').Trim('-')
    if ($t.Length -gt 40) { $t = $t.Substring(0, 40).Trim('-') }
    if (-not $t) { $t = 'gorev' }
    return $t
}

function Q([string]$s) {
    if ($s -match '["%\r\n]') { throw 'Komut argümanında desteklenmeyen karakter.' }
    '"' + $s + '"'
}

function Gunluk([string]$Mesaj, [string]$Seviye = 'BILGI') {
    $satir = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Seviye, $Mesaj
    $yol = Join-Path $YolGunluk ('yaratici-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    try { [IO.File]::AppendAllText($yol, $satir + "`r`n", $Utf8) } catch {}
    if ($script:Konsol) { Write-Host $satir }
}

function Kalp([string]$Durum) {
    try {
        Json-Yaz ([ordered]@{ pid = $PID; baslangic = $script:SurecBaslangici; zaman = (Simdi); durum = $Durum; gorev = $script:AktifGorev; adim = $script:AktifAdim }) (Join-Path $YolDurum 'kalp.json')
    } catch {}
}

function Sayac-Oku {
    $s = Json-Oku (Join-Path $YolDurum 'sayaclar.json')
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    if (-not $s -or $s.tarih -ne $bugun) {
        $s = [pscustomobject]@{ tarih = $bugun; claude = 0; codex = 0; tamamlanan = 0 }
    }
    return $s
}

function Sayac-Artir([string]$Ad, [int]$Miktar = 1) {
    $s = Sayac-Oku
    $eski = 0; if ($s.PSObject.Properties[$Ad]) { $eski = [int]$s.$Ad }
    Ayarla $s $Ad ($eski + $Miktar)
    Json-Yaz $s (Join-Path $YolDurum 'sayaclar.json')
}

function Kilit-Oku {
    $k = Json-Oku (Join-Path $YolDurum 'kilitler.json')
    if (-not $k) { $k = New-Object psobject }
    return $k
}

function Kilit-Koy([string]$Anahtar, [datetime]$Bitis, [string]$Neden) {
    $k = Kilit-Oku
    Ayarla $k $Anahtar ([pscustomobject]@{ bitis = $Bitis.ToString('o'); neden = $Neden })
    Json-Yaz $k (Join-Path $YolDurum 'kilitler.json')
    Gunluk ("Kilit: {0} -> {1} ({2})" -f $Anahtar, $Bitis.ToString('dd.MM HH:mm'), $Neden) 'UYARI'
}

function Kilitli([string]$Anahtar) {
    $k = Kilit-Oku
    if (-not $k.PSObject.Properties[$Anahtar]) { return $null }
    $v = $k.$Anahtar
    if ($v -and ([datetime]$v.bitis) -gt (Get-Date)) { return $v }
    return $null
}

function Codex-Exe {
    if ($Ayar.codex.exe -and (Test-Path -LiteralPath $Ayar.codex.exe -PathType Leaf)) { return [string]$Ayar.codex.exe }
    if ($script:CodexYolu -and (Test-Path -LiteralPath $script:CodexYolu)) { return $script:CodexYolu }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg) {
        $a = Join-Path $pkg.InstallLocation 'app\resources\codex.exe'
        if (Test-Path -LiteralPath $a) { $script:CodexYolu = $a; return $a }
    }
    $c = Get-Command codex -ErrorAction SilentlyContinue
    if ($c) { $script:CodexYolu = $c.Source; return $c.Source }
    return $null
}

function Surec-Calistir {
    param(
        [Parameter(Mandatory)][string]$Komut,   # cmd.exe içinde çalışacak komut (yönlendirmeler hariç)
        [string]$Girdi = '',
        [Parameter(Mandatory)][string]$Cikti,
        [string]$Hata = '',                     # boşsa stderr çıktıya eklenir
        [Parameter(Mandatory)][string]$Klasor,
        [int]$ZamanAsimiDk = 30,
        [string]$Etiket = 'surec'
    )
    $ic = $Komut
    if ($Girdi) { $ic += ' < ' + (Q $Girdi) }
    $ic += ' > ' + (Q $Cikti)
    if ($Hata) { $ic += ' 2> ' + (Q $Hata) } else { $ic += ' 2>&1' }
    $bas = Get-Date
    $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList ('/d /s /c "' + $ic + '"') `
        -WorkingDirectory $Klasor -WindowStyle Hidden -PassThru
    $null = $p.Handle
    $asim = $false
    while (-not $p.WaitForExit(15000)) {
        Kalp "$Etiket çalışıyor"
        if (((Get-Date) - $bas).TotalMinutes -ge $ZamanAsimiDk) {
            $asim = $true
            Gunluk "$Etiket zaman aşımına uğradı ($ZamanAsimiDk dk), süreç ağacı sonlandırılıyor" 'UYARI'
            & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $p.Id 2>$null | Out-Null
            $null = $p.WaitForExit(20000)
            break
        }
    }
    $kod = -1
    if (-not $asim) { $kod = $p.ExitCode }
    return [pscustomobject]@{ kod = $kod; zaman_asimi = $asim; sure_sn = [int]((Get-Date) - $bas).TotalSeconds }
}

function Sablon-Doldur([string]$SablonAdi, [hashtable]$Degerler) {
    $s = Metin-Oku (Join-Path $YolIstem $SablonAdi)
    if (-not $s) { throw "İstem şablonu bulunamadı: $SablonAdi" }
    $d = $Degerler
    $deg = [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $ad = $m.Groups[1].Value
        if ($d.ContainsKey($ad)) { return [string]$d[$ad] }
        return $m.Value
    }.GetNewClosure()
    return [regex]::Replace($s, '\{([A-Z_]+)\}', $deg)
}

function Karar-Oku([string]$Metin) {
    $m = [regex]::Match($Metin, '(?m)^\W{0,4}KARAR\W{0,4}\s*([A-ZÇĞİÖŞÜ_]+)')
    if ($m.Success) { return $m.Groups[1].Value.ToUpperInvariant() }
    return ''
}

function Alan-Oku([string]$Metin, [string]$Ad) {
    $m = [regex]::Match($Metin, '(?m)^\W{0,4}' + $Ad + '\W{0,4}\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.Trim('*', ' ', '`') }
    return ''
}

function Arac-Uygun($Giris) {
    $arac = [string]$Giris.arac
    $sinir = 0
    if ($Ayar.gunluk_sinir.PSObject.Properties[$arac]) { $sinir = [int]$Ayar.gunluk_sinir.$arac }
    $s = Sayac-Oku
    $kullanilan = 0; if ($s.PSObject.Properties[$arac]) { $kullanilan = [int]$s.$arac }
    if ($sinir -gt 0 -and $kullanilan -ge $sinir) { return "günlük sınır doldu ($kullanilan/$sinir)" }
    $kl = Kilitli $arac
    if ($kl) { return "$($kl.neden) ($(([datetime]$kl.bitis).ToString('HH:mm'))'e kadar)" }
    $kl = Kilitli ("{0}:{1}" -f $arac, $Giris.model)
    if ($kl) { return "$($kl.neden) ($(([datetime]$kl.bitis).ToString('HH:mm'))'e kadar)" }
    switch ($arac) {
        'claude' {
            if (-not (Test-Path -LiteralPath $Ayar.claude.exe -ErrorAction SilentlyContinue)) { return 'claude.exe bulunamadı' }
            # İsteğe bağlı kullanım dosyası ile kullanıcının kalan hakkını koru
            $kd = Json-Oku $Ayar.claude.kullanim_dosyasi
            if ($kd -and $kd.guncelleme_zamani) {
                $yas = ((Get-Date) - [datetime]$kd.guncelleme_zamani).TotalHours
                if ($yas -lt [double]$Ayar.claude.kullanim_dosyasi_gecerlilik_saat -and [int]$kd.kalan_yuzde -lt [int]$Ayar.claude.min_kalan_yuzde) {
                    return "Claude kullanım hakkı az (kalan %$($kd.kalan_yuzde))"
                }
            }
        }
        'codex'  { if (-not (Codex-Exe)) { return 'codex.exe bulunamadı' } }
        default  { return "bilinmeyen araç: $arac" }
    }
    return $null
}

function Sonuc([bool]$Basarili, [string]$Metin, [string]$Hata, $Surec) {
    $sure = 0; if ($Surec) { $sure = $Surec.sure_sn }
    return [pscustomobject]@{ basarili = $Basarili; metin = $Metin; hata = $Hata; sure_sn = $sure; arac = ''; model = '' }
}

function Claude-Hata-Isle([string]$Hata) {
    if ($Hata -match '(?i)\b401\b|authenticat|oauth|not logged in|invalid api key') {
        Kilit-Koy 'claude' (Get-Date).AddHours(2) 'Claude CLI girişi geçersiz'
        Bildir -Baslik 'Claude girişi gerekli' -Metin 'Arka plandaki Claude CLI oturumu geçersiz. Bir terminalde "claude auth login" çalıştır. Uygun olduğunda ortak araç zincirindeki sonraki araç denenir.' -Anahtar 'claude-giris' -Onem 'yuksek' -AralikDk 720
    } elseif ($Hata -match '(?i)usage limit|limit reached|hit your limit|rate.?limit|\b429\b|quota|overloaded|\b529\b') {
        $bitis = (Get-Date).AddMinutes(60)
        $m = [regex]::Match($Hata, '\|(\d{10})')
        if ($m.Success) { $bitis = [DateTimeOffset]::FromUnixTimeSeconds([int64]$m.Groups[1].Value).LocalDateTime.AddMinutes(2) }
        Kilit-Koy 'claude' $bitis 'Claude kullanım sınırı'
        Bildir -Baslik 'Claude limiti doldu' -Metin ("Claude {0}'e kadar dinleniyor; işi Codex devraldı." -f $bitis.ToString('HH:mm')) -Anahtar 'claude-limit' -AralikDk 180
    }
}

function Claude-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false) {
    $araclar = 'Read,Glob,Grep'; $mod = 'dontAsk'
    if ($Yazabilir) { $araclar = 'Read,Glob,Grep,Edit,Write'; $mod = 'acceptEdits' }
    $zaman = [int]$Ayar.zaman_asimi_dk.claude
    $komut = (Q $Ayar.claude.exe) + " -p --output-format json --no-session-persistence --model $($G.model)"
    if ($TamYetki -or $Yazabilir) { throw 'Creativity Office ajanları yalnızca okuma yetkisiyle çalışır.' }
    $komut += " --tools $araclar --allowedTools $araclar --permission-mode $mod"
    if ($G.efor) { $komut += " --effort $($G.efor)" }
    $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'claude'
    if ($s.zaman_asimi) { return (Sonuc $false '' "zaman aşımı ($zaman dk)" $s) }
    $ham = Metin-Oku $Out
    $j = $null
    try { $j = $ham | ConvertFrom-Json } catch {}
    if (-not $j) {
        $h = "çıktı çözülemedi (kod $($s.kod)): " + (Kisalt ((Son-Satirlar (Metin-Oku $Err) 6) + ' ' + $ham) 300)
        Claude-Hata-Isle $h
        return (Sonuc $false '' $h $s)
    }
    if ($s.kod -ne 0 -or $j.is_error -or $j.subtype -ne 'success') {
        $h = Kisalt ("{0} {1}" -f $j.subtype, $j.result) 300
        Claude-Hata-Isle $h
        return (Sonuc $false '' $h $s)
    }
    return (Sonuc $true ([string]$j.result) '' $s)
}

function Codex-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$SonMesaj, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false) {
    $exe = Codex-Exe
    $kum = 'read-only'; if ($Yazabilir) { $kum = 'workspace-write' }
    $zaman = [int]$Ayar.zaman_asimi_dk.codex
    if ($TamYetki -or $Yazabilir) { throw 'Creativity Office ajanları yalnızca okuma yetkisiyle çalışır.' }
    $efor = 'high'; if ($G.efor) { $efor = $G.efor }
    if (Test-Path -LiteralPath $SonMesaj) { Remove-Item -LiteralPath $SonMesaj -Force }
    $komut = (Q $exe) + " exec --skip-git-repo-check -s $kum -C $(Q $Klasor) -o $(Q $SonMesaj) -m $($G.model) -c model_reasoning_effort=$efor -"
    $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'codex'
    if ($s.zaman_asimi) { return (Sonuc $false '' "zaman aşımı ($zaman dk)" $s) }
    $metin = Metin-Oku $SonMesaj
    if ($s.kod -ne 0 -or -not $metin.Trim()) {
        # stderr tüm oturumu (istem dahil) içerir; sınıflandırma için yalnızca kuyruğa bak
        $kuyruk = Son-Satirlar ((Metin-Oku $Err) + "`n" + (Metin-Oku $Out)) 25
        if ($kuyruk -match '(?i)usage limit|rate.?limit|\b429\b|quota|exceeded your') {
            Kilit-Koy ("codex:{0}" -f $G.model) (Get-Date).AddMinutes(60) 'Codex kullanım sınırı'
        } elseif ($kuyruk -match '(?i)model.{0,40}(not found|does not exist|not supported|unsupported|invalid)') {
            Kilit-Koy ("codex:{0}" -f $G.model) (Get-Date).AddHours(6) 'model kullanılamıyor'
        } elseif ($kuyruk -match '(?i)\b401\b|unauthorized|not logged in|please log ?in') {
            Kilit-Koy 'codex' (Get-Date).AddHours(2) 'Codex girişi geçersiz'
            Bildir -Baslik 'Codex girişi gerekli' -Metin 'Codex/ChatGPT oturumu geçersiz görünüyor. Codex uygulamasını açıp giriş yap.' -Anahtar 'codex-giris' -Onem 'yuksek' -AralikDk 720
        }
        return (Sonuc $false '' ("kod {0}: {1}" -f $s.kod, (Kisalt (Son-Satirlar $kuyruk 4) 300)) $s)
    }
    return (Sonuc $true $metin '' $s)
}

function Ajan-Cagir {
    param(
        [Parameter(Mandatory)][string]$Rol,
        [Parameter(Mandatory)][string]$Istem,
        [Parameter(Mandatory)][string]$Klasor,
        [Parameter(Mandatory)][string]$KayitKlasoru,
        [Parameter(Mandatory)][string]$Etiket,
        [switch]$Yazabilir,
        [string[]]$Haric = @(),     # bu araçları atla (ör. denetçi geliştiriciyle aynı model olmasın)
        [switch]$TamYetki           # Uyumluluk parametresi; bu uygulamada reddedilir
    )
    if ($Yazabilir -or $TamYetki) { throw 'Yaratıcı ofis ajanları yalnızca okuma yetkisiyle çalışır.' }
    if (-not (Test-Path -LiteralPath $KayitKlasoru)) { New-Item -ItemType Directory -Force $KayitKlasoru | Out-Null }
    $notlar = @()
    foreach ($g in @($Ayar.roller.$Rol)) {
        $kimlik = "{0}/{1}" -f $g.arac, $g.model
        if ($Haric -contains $kimlik) { $notlar += "${kimlik}: atlandı"; continue }
        $neden = Arac-Uygun $g
        if ($neden) { $notlar += "${kimlik}: $neden"; continue }
        $ad = '{0}-{1}-{2}' -f $Etiket, $g.arac, ([string]$g.model -replace '[^A-Za-z0-9._-]', '_')
        $istemYolu = Join-Path $KayitKlasoru "$ad.istem.md"
        $out = Join-Path $KayitKlasoru "$ad.out.txt"
        $err = Join-Path $KayitKlasoru "$ad.err.txt"
        $son = Join-Path $KayitKlasoru "$ad.son.md"
        Metin-Yaz $istemYolu $Istem
        Sayac-Artir ([string]$g.arac)
        $script:AktifAdim = "$Etiket ($kimlik)"
        Kalp 'ajan'
        Gunluk "$Rol -> $kimlik başlıyor [$($script:AktifGorev) / $Etiket]"
        try {
            switch ($g.arac) {
                'claude' { $r = Claude-Calistir $g $istemYolu $out $err $Klasor $false }
                'codex'  { $r = Codex-Calistir $g $istemYolu $out $err $son $Klasor $false }
                default { throw "Bilinmeyen araç: $($g.arac)" }
            }
        } catch { $r = Sonuc $false '' $_.Exception.Message $null }
        if ($r.basarili) {
            $r.arac = [string]$g.arac; $r.model = [string]$g.model
            Gunluk "$Rol -> $kimlik bitti ($($r.sure_sn) sn)"
            return $r
        }
        Gunluk "$Rol -> $kimlik başarısız: $($r.hata)" 'UYARI'
        $notlar += "${kimlik}: $($r.hata)"
    }
    return [pscustomobject]@{ basarili = $false; metin = ''; hata = ($notlar -join ' | '); sure_sn = 0; arac = ''; model = '' }
}

function Toast-Goster([string]$Baslik, [string]$Metin) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $rapor = 'file:///' + ((Join-Path $YolRapor 'son-rapor.md') -replace '\\', '/')
        $e = { param($x) [Security.SecurityElement]::Escape([string]$x) }
        $xml = '<toast activationType="protocol" launch="{0}"><visual><binding template="ToastGeneric"><text>{1}</text><text>{2}</text></binding></visual></toast>' -f (& $e $rapor), (& $e $Baslik), (& $e $Metin)
        $d = New-Object Windows.Data.Xml.Dom.XmlDocument
        $d.LoadXml($xml)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($d))
    } catch { Gunluk "Masaüstü bildirimi gösterilemedi: $($_.Exception.Message)" 'UYARI' }
}

function Ntfy-Gonder([string]$Baslik, [string]$Metin, [string]$Onem) {
    try {
        $tel = $Ayar.bildirim.telefon
        $oncelik = 3; if ($Onem -eq 'yuksek') { $oncelik = 4 }
        $govde = [ordered]@{ topic = [string]$tel.ntfy_konu; title = $Baslik; message = $Metin; tags = @('robot'); priority = $oncelik } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri ([string]$tel.ntfy_sunucu).TrimEnd('/') -Body ([Text.Encoding]::UTF8.GetBytes($govde)) `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 -UseBasicParsing | Out-Null
    } catch { Gunluk "Telefon bildirimi gönderilemedi: $($_.Exception.Message)" 'UYARI' }
}

function Bildir {
    param(
        [Parameter(Mandatory)][string]$Baslik,
        [Parameter(Mandatory)][string]$Metin,
        [string]$Anahtar = '',
        [ValidateSet('normal', 'yuksek')][string]$Onem = 'normal',
        [int]$AralikDk = -1
    )
    if ($AralikDk -lt 0) { $AralikDk = [int]$Ayar.bildirim.ayni_bildirim_arasi_dk }
    if ($Anahtar) {
        $zy = Join-Path $YolDurum 'bildirim_zamanlari.json'
        $z = Json-Oku $zy
        if (-not $z) { $z = New-Object psobject }
        if ($z.PSObject.Properties[$Anahtar] -and ((Get-Date) - [datetime]$z.$Anahtar).TotalMinutes -lt $AralikDk) {
            Gunluk "Bildirim bastırıldı (aynı konu, $AralikDk dk içinde): $Baslik"
            return
        }
        Ayarla $z $Anahtar (Simdi)
        Json-Yaz $z $zy
    }
    Gunluk "BİLDİRİM: $Baslik | $Metin"
    try {
        $satir = [ordered]@{ zaman = (Simdi); baslik = $Baslik; metin = $Metin; onem = $Onem } | ConvertTo-Json -Compress
        [IO.File]::AppendAllText((Join-Path $YolDurum 'bildirimler.jsonl'), $satir + "`n", $Utf8)
    } catch {}
    if ($Ayar.bildirim.masaustu) { Toast-Goster $Baslik $Metin }
    $tel = $Ayar.bildirim.telefon
    if ($tel -and $tel.kanal -eq 'ntfy' -and $tel.ntfy_konu) { Ntfy-Gonder $Baslik $Metin $Onem }
}

function Gorev-Klasoru([string]$Id) {
    Kimlik-Dogrula $Id
    Join-Path $YolGorev $Id
}

function Gorev-Oku([string]$Id) { Json-Oku (Join-Path (Gorev-Klasoru $Id) 'durum.json') }

function Gorev-Kaydet($G) {
    Ayarla $G 'guncelleme' (Simdi)
    Json-Yaz $G (Join-Path (Gorev-Klasoru $G.id) 'durum.json')
}

function Gorevleri-Listele {
    $liste = @()
    foreach ($d in (Get-ChildItem -LiteralPath $YolGorev -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $g = Json-Oku (Join-Path $d.FullName 'durum.json')
        if ($g) { $liste += $g }
    }
    return $liste
}

function Kimlik-Dogrula([string]$Id) {
    if ($Id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,119}$') { throw "Geçersiz görev kimliği: $Id" }
}
function Ayarlari-Yukle {
    $script:Ayar = Json-Oku (Join-Path $Kok 'ayarlar.json')
    if (-not $Ayar) { throw 'Yaratıcı ofis ayarlar.json okunamadı.' }
    if ([int]$Ayar.revizyon_siniri -lt 0 -or [int]$Ayar.revizyon_siniri -gt 3) { throw 'revizyon_siniri 0-3 arasında olmalıdır.' }
    foreach ($ad in @('bos_bekleme_sn','adim_arasi_sn','hata_bekleme_dk','max_adim_denemesi','bekci_dk','izleme_araligi_sn')) {
        if ([double]$Ayar.dongu.$ad -le 0) { throw "dongu.$ad pozitif olmalıdır." }
    }
    if ($Ayar.dongu.calisma_saatleri -notmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]-(?:(?:[01][0-9]|2[0-3]):[0-5][0-9]|24:00)$') {
        throw 'calisma_saatleri HH:mm-HH:mm biçiminde olmalıdır.'
    }
    $kadro = Json-Oku (Join-Path $Kok 'kadro.json')
    if (-not $kadro -or @($kadro.uyeler).Count -ne 6) { throw 'kadro.json altı ajan içermelidir.' }
    if (@($kadro.uyeler.anahtar | Sort-Object -Unique).Count -ne 6) { throw 'Kadro anahtarları benzersiz olmalıdır.' }
    foreach ($uye in $kadro.uyeler) {
        if ($uye.anahtar -notin @('fikirci','elestirmen','planlamaci','maliyet','karar-verici','puanlayici')) { throw 'Bilinmeyen kadro rolü.' }
        Ayarla $Ayar.roller $uye.anahtar @($Ayar.roller.ortak)
    }
    Ayarla $Ayar.roller 'teslim' @($Ayar.roller.ortak)
    if (-not @($Ayar.roller.ortak).Count) { throw 'Ortak araç zinciri boş.' }
    foreach ($g in @($Ayar.roller.ortak)) {
        if ($g.arac -notin @('claude','codex') -or $g.model -notmatch '^[a-zA-Z0-9._-]+$' -or ($g.efor -and $g.efor -notmatch '^[a-zA-Z0-9_-]+$')) { throw 'Geçersiz araç/model/efor ayarı.' }
        if ([int]$Ayar.zaman_asimi_dk.($g.arac) -le 0 -or [int]$Ayar.gunluk_sinir.($g.arac) -le 0) { throw 'Araç zaman aşımı ve günlük sınırı pozitif olmalıdır.' }
    }
    if (-not $Ayar.claude.exe) {
        $c = Get-Command claude.exe -ErrorAction SilentlyContinue
        if ($c) { $Ayar.claude.exe = $c.Source }
    }
}
function Ofis-Kilidi([string]$Ad) {
    # Aynı kurulumdaki döngü ve yönetim komutları görev dosyalarını birlikte değiştirmez.
    $dosya = Join-Path $YolDurum "$Ad.lock"
    try { return [IO.File]::Open($dosya, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw "Yaratıcı ofis kilidi alınamadı ($Ad); çalışan işlem bittikten sonra yeniden deneyin." }
}
function Kalpli-Bekle([int]$Saniye, [string]$Mesaj = 'bekliyor') {
    $bitis = (Get-Date).AddSeconds($Saniye)
    while ((Get-Date) -lt $bitis) {
        Kalp $Mesaj
        if (Test-Path -LiteralPath (Join-Path $Kok 'DURDUR')) { return }
        Start-Sleep -Milliseconds ([int][Math]::Min(1000, [Math]::Max(1, ($bitis - (Get-Date)).TotalMilliseconds)))
    }
}
