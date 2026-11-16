param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Dosya
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle
if (-not (Test-Path -LiteralPath $Dosya -PathType Leaf)) { throw "Çıktı dosyası bulunamadı: $Dosya" }
$metin = Metin-Oku (Resolve-Path -LiteralPath $Dosya).Path
if (-not $metin.Trim()) { throw 'Uygulama çıktısı boş olamaz.' }
$kilit = Ofis-Kilidi 'gorev'
try {
    $g = Gorev-Oku $Id
    if (-not $g -or $g.asama -ne 'bekleme' -or $g.teslim_turu -ne 'yerel') {
        throw 'Yalnızca yerel teslimi bekleyen göreve çıktı eklenebilir.'
    }
    Metin-Yaz (Join-Path (Gorev-Klasoru $Id) 'uygulama-ciktisi.md') $metin
    $g.gecmis = @($g.gecmis) + [pscustomobject]@{ zaman = (Simdi); onceki = 'bekleme'; yeni = 'puanlama'; revizyon = $g.revizyon; neden = 'Yerel uygulama çıktısı eklendi' }
    $g.asama = 'puanlama'; $g.deneme = 0; $g.son_hata = ''; $g.sonraki_deneme = $null
    Gorev-Kaydet $g
    Write-Output $g
} finally { $kilit.Dispose() }
