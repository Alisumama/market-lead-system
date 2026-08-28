<#
.SYNOPSIS
    Builds the Bastak Leads Windows release and packages it into an installer.

.DESCRIPTION
    Runs `flutter build windows --release`, then compiles
    windows\installer\bastak_leads.iss with Inno Setup. The version is read
    from pubspec.yaml so the installer, the exe and pubspec never drift apart.

    Inno Setup 6 must be installed:  winget install JRSoftware.InnoSetup

.PARAMETER SkipBuild
    Package the existing build\windows\x64\runner\Release folder without
    re-running the Flutter build.

.PARAMETER SignThumbprint
    SHA-1 thumbprint of an Authenticode certificate in the current user's
    certificate store to sign the exe and installer with. Defaults to the
    BASTAK_SIGN_THUMBPRINT environment variable.

.PARAMETER SignPfx
    Path to a .pfx code-signing certificate (alternative to -SignThumbprint).
    Defaults to BASTAK_SIGN_PFX; password from BASTAK_SIGN_PFX_PASSWORD.

.PARAMETER TimestampUrl
    RFC-3161 timestamp server, so signatures stay valid after the cert expires.

    Signing is optional but strongly recommended: without it Windows SmartScreen
    warns on every install/update. When no cert is supplied the build still runs,
    unsigned, with a warning.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\build_windows_installer.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$SignThumbprint = $env:BASTAK_SIGN_THUMBPRINT,
    [string]$SignPfx = $env:BASTAK_SIGN_PFX,
    [string]$SignPfxPassword = $env:BASTAK_SIGN_PFX_PASSWORD,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# --- code signing helper -----------------------------------------------------
$script:signtool = $null
function Get-SignTool {
    if ($script:signtool) { return $script:signtool }
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:signtool = $cmd.Source; return $script:signtool }
    # Fall back to the newest signtool shipped with the Windows 10/11 SDK.
    $found = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
        -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' } |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { $script:signtool = $found.FullName }
    return $script:signtool
}

function Invoke-Sign([string]$file) {
    if (-not $SignThumbprint -and -not $SignPfx) {
        Write-Warning "No code-signing cert configured -- '$([IO.Path]::GetFileName($file))' will be UNSIGNED (SmartScreen will warn users). Set BASTAK_SIGN_THUMBPRINT or BASTAK_SIGN_PFX."
        return
    }
    $tool = Get-SignTool
    if (-not $tool) { throw "signtool.exe not found. Install the Windows SDK, or add signtool to PATH." }
    $signArgs = @('sign', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256')
    if ($SignThumbprint) {
        $signArgs += @('/sha1', $SignThumbprint)
    } else {
        $signArgs += @('/f', $SignPfx)
        if ($SignPfxPassword) { $signArgs += @('/p', $SignPfxPassword) }
    }
    $signArgs += $file
    & $tool @signArgs
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $file ($LASTEXITCODE)" }
    Write-Host "Signed $([IO.Path]::GetFileName($file))" -ForegroundColor Green
}

# --- version from pubspec.yaml (e.g. "version: 2.1.1+2") ---------------------
$versionLine = Select-String -Path (Join-Path $repo 'pubspec.yaml') `
    -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)' | Select-Object -First 1
if (-not $versionLine) { throw "Could not parse 'version:' from pubspec.yaml" }
$appVersion  = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$versionInfo = "$appVersion.$buildNumber"
Write-Host "Version $appVersion (build $buildNumber)" -ForegroundColor Cyan

# --- flutter build -----------------------------------------------------------
$releaseDir = Join-Path $repo 'build\windows\x64\runner\Release'
if (-not $SkipBuild) {
    Write-Host 'Building Flutter Windows release...' -ForegroundColor Cyan
    # Belt-and-suspenders for the same STL1011 <experimental/coroutine> error the
    # windows/CMakeLists.txt define guards against: cl.exe also honours the CL
    # env var, so newer MSVC toolsets build cleanly however the plugins compile.
    $env:CL = (("$env:CL /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS").Trim())
    Push-Location $repo
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $releaseDir 'bastak_leads.exe'))) {
    throw "No build found at $releaseDir. Run without -SkipBuild first."
}

# Guard against shipping a bundle that would fail on a machine with no VC++
# redistributable -- these are copied in by windows\CMakeLists.txt.
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path (Join-Path $releaseDir $dll))) {
        throw "$dll missing from the release bundle; the installer would produce an app that does not start on a clean Windows machine."
    }
}

# Sign the app exe before it is packaged, so the installed program is trusted
# too (not just setup.exe).
Invoke-Sign (Join-Path $releaseDir 'bastak_leads.exe')

# --- where the app keeps its data -------------------------------------------
# path_provider's getApplicationSupportDirectory() builds this from the exe's
# CompanyName and ProductName, so read them straight out of Runner.rc instead of
# duplicating the value in the .iss where it can drift when the product is renamed.
$rc = Get-Content (Join-Path $repo 'windows\runner\Runner.rc') -Raw
$company = [regex]::Match($rc, 'VALUE\s+"CompanyName",\s*"([^"]+)"').Groups[1].Value
$product = [regex]::Match($rc, 'VALUE\s+"ProductName",\s*"([^"]+)"').Groups[1].Value
if (-not $company -or -not $product) { throw "Could not read CompanyName/ProductName from Runner.rc" }
$appDataDir = "$company\$product"
Write-Host "App data dir: %APPDATA%\$appDataDir" -ForegroundColor Cyan

# --- locate Inno Setup -------------------------------------------------------
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) { throw "Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup" }

# --- compile the installer ---------------------------------------------------
$outputDir = Join-Path $repo 'build\windows\installer'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$iss = Join-Path $repo 'windows\installer\bastak_leads.iss'

# Wizard artwork is derived from assets\, so regenerate it on every build to
# pick up any brand change rather than shipping a stale bitmap.
$brandingDir = Join-Path $repo 'build\windows\branding'
# Dot-calling a .ps1 does not set $LASTEXITCODE (that is for native exes), and
# the generator throws on failure, so check that it actually produced artwork.
& (Join-Path $PSScriptRoot 'make_installer_branding.ps1') -OutputDir $brandingDir
if (-not (Test-Path (Join-Path $brandingDir 'WizardImage-164x314.bmp'))) {
    throw "branding generation produced no wizard artwork in $brandingDir"
}

Write-Host 'Compiling installer...' -ForegroundColor Cyan
& $iscc "/DAppVersion=$appVersion" "/DVersionInfo=$versionInfo" `
        "/DBuildDir=$releaseDir" "/DOutputDir=$outputDir" `
        "/DBrandingDir=$brandingDir" "/DAppDataDir=$appDataDir" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Get-Item (Join-Path $outputDir "bastak_leads-$appVersion-windows-x64-setup.exe")

# Sign the finished installer, then hash it for the update manifest.
Invoke-Sign $setup.FullName
$sha = (Get-FileHash -Algorithm SHA256 $setup.FullName).Hash.ToLower()

$assetUrl = "https://github.com/Alisumama/market-lead-system/releases/download/v$appVersion/$($setup.Name)"

Write-Host ''
Write-Host ("Installer: {0}" -f $setup.FullName) -ForegroundColor Green
Write-Host ("Size:      {0:N1} MB" -f ($setup.Length / 1MB)) -ForegroundColor Green
Write-Host ("SHA-256:   {0}" -f $sha) -ForegroundColor Green
Write-Host ''
Write-Host 'Next: create GitHub release tag ' -NoNewline
Write-Host "v$appVersion" -ForegroundColor Yellow -NoNewline
Write-Host ", upload the installer, then set Firestore config/appVersion to:"
Write-Host "  version:   $appVersion"
Write-Host "  url:       $assetUrl"
Write-Host "  sha256:    $sha"
Write-Host "  mandatory: false"
Write-Host '(see RELEASING.md)'
