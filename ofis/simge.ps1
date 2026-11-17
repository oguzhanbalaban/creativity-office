# Uygulama simgeleri (telefon ana ekranı, masaüstü kısayolu). Yalnızca System.Drawing kullanır; ağ gerekmez.
# Dot-source edilir: . .\ofis\simge.ps1; Simge-Uret <klasör> [-Ico]
function Simge-Ciz([int]$Boyut) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object Drawing.Bitmap $Boyut, $Boyut
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $o = $Boyut / 32.0
    $renk = { param($h) [Drawing.ColorTranslator]::FromHtml($h) }
    $g.Clear((& $renk '#1b1524'))
    # ampul (fikir) + altı ajan rengi halkası
    $ajanlar = @('#f59e0b', '#ef4444', '#3b82f6', '#10b981', '#8b5cf6', '#ec4899')
    for ($i = 0; $i -lt 6; $i++) {
        $a = [Math]::PI * 2 * $i / 6 - [Math]::PI / 2
        $x = 16 + [Math]::Cos($a) * 11; $y = 15 + [Math]::Sin($a) * 11
        $f = New-Object Drawing.SolidBrush (& $renk $ajanlar[$i])
        $g.FillEllipse($f, [float](($x - 2.6) * $o), [float](($y - 2.6) * $o), [float](5.2 * $o), [float](5.2 * $o)); $f.Dispose()
    }
    $f = New-Object Drawing.SolidBrush (& $renk '#fde68a')
    $g.FillEllipse($f, [float](10.5 * $o), [float](8 * $o), [float](11 * $o), [float](11 * $o)); $f.Dispose()
    $f = New-Object Drawing.SolidBrush (& $renk '#fbbf24')
    $g.FillRectangle($f, [float](13 * $o), [float](17.5 * $o), [float](6 * $o), [float](3 * $o)); $f.Dispose()
    $f = New-Object Drawing.SolidBrush (& $renk '#94a3b8')
    $g.FillRectangle($f, [float](13.5 * $o), [float](20.5 * $o), [float](5 * $o), [float](1.6 * $o))
    $g.FillRectangle($f, [float](14 * $o), [float](22.4 * $o), [float](4 * $o), [float](1.4 * $o)); $f.Dispose()
    $g.Dispose()
    return $bmp
}
function Simge-Uret([string]$Klasor, [switch]$Ico) {
    foreach ($boyut in 180, 192, 512) {
        $bmp = Simge-Ciz $boyut
        try { $bmp.Save((Join-Path $Klasor "simge-$boyut.png"), [Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
    }
    if ($Ico) {
        # PNG gömülü tek görüntülü ICO (Windows Vista+)
        $bmp = Simge-Ciz 256
        $ms = New-Object IO.MemoryStream
        try { $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
        $png = $ms.ToArray(); $ms.Dispose()
        $fs = [IO.File]::Create((Join-Path $Klasor 'ofis.ico'))
        try {
            $w = New-Object IO.BinaryWriter $fs
            $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)
            $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$png.Length); $w.Write([uint32]22)
            $w.Write($png); $w.Flush()
        } finally { $fs.Dispose() }
    }
}
