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

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\build_windows_installer.ps1
#>
[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

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

Write-Host 'Compiling installer...' -ForegroundColor Cyan
& $iscc "/DAppVersion=$appVersion" "/DVersionInfo=$versionInfo" `
        "/DBuildDir=$releaseDir" "/DOutputDir=$outputDir" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Get-Item (Join-Path $outputDir "bastak_leads-$appVersion-windows-x64-setup.exe")
Write-Host ''
Write-Host ("Installer: {0}" -f $setup.FullName) -ForegroundColor Green
Write-Host ("Size:      {0:N1} MB" -f ($setup.Length / 1MB)) -ForegroundColor Green
