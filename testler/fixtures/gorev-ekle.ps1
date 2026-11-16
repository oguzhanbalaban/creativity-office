# Yalnızca çevrimdışı testler için en küçük teslim sözleşmesi.
param([string]$Proje, [string]$Baslik, [string]$Aciklama, [string[]]$Kabul)
$ErrorActionPreference = 'Stop'
$id = [guid]::NewGuid().ToString('N')
$klasor = Join-Path (Join-Path $PSScriptRoot 'gorevler') $id
New-Item -ItemType Directory -Path $klasor -Force | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $klasor 'gorev.md'), "$Baslik`n$Aciklama`n$($Kabul -join "`n")", $utf8)
$durum = [pscustomobject]@{ id = $id; asama = 'yeni'; proje = $Proje; son_hata = '' }
[IO.File]::WriteAllText((Join-Path $klasor 'durum.json'), ($durum | ConvertTo-Json), $utf8)
$durum
