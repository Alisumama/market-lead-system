<#
.SYNOPSIS
    Generates the Inno Setup wizard artwork from the app's brand assets.

.DESCRIPTION
    Inno Setup only accepts BMP for the wizard images, so the brand PNGs are
    composited into bitmaps here rather than being referenced directly. Output
    is written under build\ and is not committed -- the PNGs in assets\ stay the
    single source of truth, so re-running this picks up any brand refresh.

    Each image is emitted at several sizes; Inno picks the one matching the
    user's DPI at runtime.

      WizardImage-*.bmp       left panel on the Welcome / Finished pages:
                              the white knockout logo on a brand-green gradient
      WizardSmallImage-*.bmp  header badge on the inner pages: the app icon,
                              on white to match the wizard's header strip

.PARAMETER OutputDir
    Directory to write the .bmp files into. Created if missing.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repo      = Split-Path -Parent $PSScriptRoot
$logoWhite = Join-Path $repo 'assets\splash\splash-logo-4x-white.png'
$appIcon   = Join-Path $repo 'assets\icon\app_icon.png'
foreach ($f in @($logoWhite, $appIcon)) {
    if (-not (Test-Path $f)) { throw "Brand asset not found: $f" }
}

# Bastak palette, from lib\theme (brandGreenDark / brandGreen / accentGreen).
$greenDark   = [System.Drawing.Color]::FromArgb(0x1E, 0x7A, 0x2A)
$green       = [System.Drawing.Color]::FromArgb(0x33, 0xA3, 0x37)
$accentGreen = [System.Drawing.Color]::FromArgb(0x9F, 0xC4, 0x27)

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Set-Quality([System.Drawing.Graphics]$g) {
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
}

# Scale src to fit inside (boxW x boxH) without distortion, and return the
# centred rectangle to draw it into.
function Get-FitRect($src, [int]$cx, [int]$cy, [double]$boxW, [double]$boxH) {
    $scale = [Math]::Min($boxW / $src.Width, $boxH / $src.Height)
    $w = $src.Width * $scale
    $h = $src.Height * $scale
    New-Object System.Drawing.RectangleF(($cx - $w / 2), ($cy - $h / 2), $w, $h)
}

function New-WizardImage([int]$W, [int]$H, $logo) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    Set-Quality $g

    # Vertical brand gradient, dark at the top. In the modern wizard style this
    # panel carries no text of its own, so it is free to be a plain brand field.
    $rect  = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $greenDark, $green, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()

    # White knockout logo, centred in the upper portion of the panel.
    $g.DrawImage($logo, (Get-FitRect $logo ($W / 2) ($H * 0.42) ($W * 0.74) ($H * 0.34)))

    # Short accent rule tucked under the lockup, echoing the "instruments"
    # green in the logo. Kept close to the mark so it reads as part of the
    # lockup rather than as a stray element floating in the panel.
    $barH = [Math]::Max(2, [int]($H * 0.010))
    $barW = [int]($W * 0.22)
    $accentBrush = New-Object System.Drawing.SolidBrush($accentGreen)
    $g.FillRectangle($accentBrush, [int](($W - $barW) / 2), [int]($H * 0.63), $barW, $barH)
    $accentBrush.Dispose()

    $g.Dispose()
    return $bmp
}

function New-SmallImage([int]$W, [int]$H, $icon) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    Set-Quality $g
    # The inner-page header strip is white; matching it makes the rounded icon
    # read as a floating mark rather than a pasted tile.
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($icon, (Get-FitRect $icon ($W / 2) ($H / 2) ($W * 0.94) ($H * 0.94)))
    $g.Dispose()
    return $bmp
}

$logo = [System.Drawing.Image]::FromFile($logoWhite)
$icon = [System.Drawing.Image]::FromFile($appIcon)
try {
    # Sizes Inno Setup 6 looks for when scaling the modern wizard for high DPI.
    $large = @(@(164, 314), @(192, 386), @(246, 459), @(328, 628))
    $small = @(@(55, 58), @(64, 68), @(83, 80), @(92, 97), @(110, 116), @(119, 123), @(138, 140), @(164, 161))

    foreach ($s in $large) {
        $b = New-WizardImage $s[0] $s[1] $logo
        $b.Save((Join-Path $OutputDir "WizardImage-$($s[0])x$($s[1]).bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
        $b.Dispose()
    }
    foreach ($s in $small) {
        $b = New-SmallImage $s[0] $s[1] $icon
        $b.Save((Join-Path $OutputDir "WizardSmallImage-$($s[0])x$($s[1]).bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
        $b.Dispose()
    }
} finally {
    $logo.Dispose()
    $icon.Dispose()
}

Write-Host ("Branding: {0} bitmaps -> {1}" -f (Get-ChildItem $OutputDir -Filter *.bmp).Count, $OutputDir)
