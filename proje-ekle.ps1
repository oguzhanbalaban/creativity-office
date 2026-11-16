param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Konu,
    [string]$Alan = 'genel',
    [string]$Proje = '',
    [ValidateRange(1,3)][int]$Oncelik = 2
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle
if (-not $Konu.Trim()) { throw 'Konu boş olamaz.' }
if (-not $Proje) { $Proje = [string]$Ayar.varsayilan_proje }
if ($Proje -and (Test-Path -LiteralPath $Proje -PathType Container)) { $Proje = (Resolve-Path -LiteralPath $Proje).Path }
$kilit = Ofis-Kilidi 'ekleme'
try {
    $id = '{0}-{1}-{2}' -f (Get-Date).ToString('yyyyMMddHHmmss'), (Slug $Konu), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $gk = Gorev-Klasoru $id
    New-Item -ItemType Directory -Path $gk -Force | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# $Konu`n`n- Alan: $Alan`n- Hedef proje: $Proje`n`n## Amaç`n`n$Konu`n"
    $g = [pscustomobject]@{
        id = $id; baslik = $Konu; alan = $Alan; proje = $Proje; oncelik = $Oncelik
        asama = 'yeni'; revizyon = 0; deneme = 0; sonraki_deneme = $null
        son_hata = ''; olusturma = (Simdi); gecmis = @(); geri_bildirimler = @()
        teslim_anahtari = ([guid]::NewGuid().ToString('N'))
    }
    Gorev-Kaydet $g
    Gunluk "Yaratıcılık görevi eklendi: $id"
    Write-Output $g
} finally { $kilit.Dispose() }
