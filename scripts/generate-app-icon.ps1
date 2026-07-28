param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Add-Type -AssemblyName System.Drawing

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Add-RoundedRectangle {
    param(
        [System.Drawing.Drawing2D.GraphicsPath]$Path,
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $diameter = $Radius * 2
    $Path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $Path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $Path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $Path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $Path.CloseFigure()
}

function New-AppIcon {
    param(
        [int]$Size,
        [string]$Path
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $background = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)),
        ([System.Drawing.Color]::FromArgb(15, 23, 42)),
        ([System.Drawing.Color]::FromArgb(30, 41, 59)),
        135
    )
    $graphics.FillRectangle($background, 0, 0, $Size, $Size)

    $scale = $Size / 1024.0
    $framePath = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RoundedRectangle -Path $framePath -X (210 * $scale) -Y (150 * $scale) -Width (604 * $scale) -Height (724 * $scale) -Radius (68 * $scale)
    $frameBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 212, 191))
    $graphics.FillPath($frameBrush, $framePath)

    $screenPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RoundedRectangle -Path $screenPath -X (270 * $scale) -Y (250 * $scale) -Width (484 * $scale) -Height (440 * $scale) -Radius (30 * $scale)
    $screenBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(2, 6, 23))
    $graphics.FillPath($screenBrush, $screenPath)

    $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240), (24 * $scale))
    $linePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $linePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    foreach ($line in @(@(340, 390, 670), @(340, 490, 710), @(340, 590, 630))) {
        $graphics.DrawLine($linePen, $line[0] * $scale, $line[1] * $scale, $line[2] * $scale, $line[1] * $scale)
    }

    $cursorPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 212, 191), (14 * $scale))
    $cursorPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $cursorPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($cursorPen, 340 * $scale, 650 * $scale, 680 * $scale, 650 * $scale)

    $recordBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(248, 113, 113))
    $recordDiameter = 50 * $scale
    $graphics.FillEllipse($recordBrush, 487 * $scale, 178 * $scale, $recordDiameter, $recordDiameter)

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $recordBrush.Dispose()
    $cursorPen.Dispose()
    $linePen.Dispose()
    $screenBrush.Dispose()
    $frameBrush.Dispose()
    $screenPath.Dispose()
    $framePath.Dispose()
    $background.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$sizes = @{
    "20x20@1x" = 20
    "20x20@2x" = 40
    "20x20@3x" = 60
    "29x29@1x" = 29
    "29x29@2x" = 58
    "29x29@3x" = 87
    "40x40@1x" = 40
    "40x40@2x" = 80
    "40x40@3x" = 120
    "60x60@2x" = 120
    "60x60@3x" = 180
    "76x76@1x" = 76
    "76x76@2x" = 152
    "83.5x83.5@2x" = 167
    "1024x1024@1x" = 1024
}

foreach ($entry in $sizes.GetEnumerator()) {
    New-AppIcon -Size $entry.Value -Path (Join-Path $OutputDirectory ("AppIcon-{0}.png" -f $entry.Key.Replace("@", "-at-")))
}
