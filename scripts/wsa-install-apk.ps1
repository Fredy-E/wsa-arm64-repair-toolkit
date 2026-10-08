<#
.SYNOPSIS
  Double-click handler: install an APK into Windows Subsystem for Android.

.DESCRIPTION
  Invoked by the .apk file association installed by Install-WsaApkAssociation.ps1.
  Connects to WSA's adb (port 58526), starting WSA if it is not running, then
  runs "adb install -r" on the opened file. Shows progress in its console window.

.PARAMETER ApkPath
  The .apk file to install (passed by the file association as "%1").
.PARAMETER AdbPath
  adb.exe path (embedded by the association installer; auto-detected otherwise).
.PARAMETER Port
  WSA adb port (default 58526).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$ApkPath,
    [string]$AdbPath,
    [int]$Port = 58526
)
$ErrorActionPreference = 'Continue'
Write-Host '=== Windows Subsystem for Android - APK Installer ==='
Write-Host ''
if (-not $ApkPath -or -not (Test-Path $ApkPath)) {
    Write-Host 'No APK file was passed. Open an .apk file, or drag one onto this script.'
    Start-Sleep -Seconds 8
    exit 1
}
if (-not $AdbPath -or -not (Test-Path $AdbPath)) {
    $onPath = Get-Command adb.exe -ErrorAction SilentlyContinue
    $AdbPath = if ($onPath) { $onPath.Source } else { 'D:\Android\sdk\platform-tools\adb.exe' }
}
if (-not (Test-Path $AdbPath)) {
    Write-Host ('adb.exe not found (looked on PATH and at ' + $AdbPath + ').')
    Write-Host 'Re-run Install-WsaApkAssociation.ps1 -AdbPath <path-to-adb.exe>.'
    Start-Sleep -Seconds 10
    exit 1
}

Write-Host ('Installing: ' + $ApkPath)
Write-Host ''

function Try-AdbConnect {
    $out = & $AdbPath connect ('127.0.0.1:' + $Port) 2>&1
    $s = ($out -join ' ')
    if (($s -match 'connected') -or ($s -match 'already')) { return $true }
    return $false
}

$ok = $false
for ($i = 0; $i -lt 3; $i++) {
    if (Try-AdbConnect) { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) {
    Write-Host 'WSA is not reachable. Starting Windows Subsystem for Android, please wait...'
    Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:appsFolder\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe!App'
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Seconds 5
        if (Try-AdbConnect) { $ok = $true; break }
    }
}
if (-not $ok) {
    Write-Host ('Could not connect to WSA adb port ' + $Port + '. Is Developer mode enabled?')
    Write-Host 'Run Enable-WsaDeveloperMode.ps1 from an unlocked session.'
    Start-Sleep -Seconds 10
    exit 1
}

$out = & $AdbPath install -r $ApkPath 2>&1
Write-Host ($out -join [Environment]::NewLine)
Write-Host ''
if (($out -join ' ') -match 'Success') {
    Write-Host 'Installed successfully. It should appear in the Android apps list.'
    Start-Sleep -Seconds 10
} else {
    Write-Host 'Install did not report Success - see output above.'
    Start-Sleep -Seconds 15
}
