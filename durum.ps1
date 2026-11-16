param([string]$Id = '', [string]$Devam = '', [string]$Iptal = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle
if ($Devam -and $Iptal) { throw 'Devam ve iptal aynı anda kullanılamaz.' }
if ($Devam -or $Iptal) {
    $hedef = $Devam; if ($Iptal) { $hedef = $Iptal }
    $kilit = Ofis-Kilidi 'gorev'
    try {
        $g = Gorev-Oku $hedef
        if (-not $g) { throw "Görev bulunamadı: $hedef" }
        if ($Devam) {
            if ($g.asama -ne 'takildi') { throw 'Yalnızca takılan görev devam ettirilebilir.' }
            $g.asama = $g.takildi_asama
            $g.deneme = 0; $g.son_hata = ''; $g.sonraki_deneme = $null
        } else {
            if ($g.asama -in @('tamam','reddedildi')) { throw 'Kapanmış görev iptal edilemez.' }
            $g.asama = 'iptal'
        }
        Gorev-Kaydet $g
        Write-Output $g
    } finally { $kilit.Dispose() }
} elseif ($Id) { Gorev-Oku $Id } else {
    Gorevleri-Listele | Select-Object id, baslik, asama, revizyon, ana_gorev_id, puan, son_hata
}
