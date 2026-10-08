<#
.SYNOPSIS
  Register (or remove) a ".apk opens in WSA" file association.

.DESCRIPTION
  Sideloaded WSA builds register no .apk handler (verified: no
  fileTypeAssociation in the manifest, no HKCR\.apk entry). This script:
    1. Copies the handler script (wsa-install-apk.ps1, next to this script)
       to -HandlerDir.
    2. Registers a ProgID "WSA.apk" and the .apk extension, so opening any
       .apk runs the handler, which installs the file into WSA over adb
       (auto-starting WSA if needed).

  The machine-wide (HKCR) part needs admin; the HKCU mirror is always set.
  Remove with -Uninstall.

  Note: AssocQueryString can still report ERROR_NO_ASSOCIATION in some
  contexts even when the association works - trust the live test.

.PARAMETER HandlerDir
  Where to keep the handler (default: %LOCALAPPDATA%\WsaApkHandler).
.PARAMETER AdbPath
  adb.exe to embed into the handler command (default: auto-detect).
.PARAMETER Uninstall
  Remove the association and the handler copy.
#>
[CmdletBinding()]
param(
    [string]$HandlerDir = (Join-Path $env:LOCALAPPDATA 'WsaApkHandler'),
    [string]$AdbPath,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
function Log($m) { Write-Host $m }

$progId = 'WSA.apk'
$handlerSrc = Join-Path $PSScriptRoot 'wsa-install-apk.ps1'

if ($Uninstall) {
    & reg.exe delete 'HKCR\.apk' /f 2>$null | Out-Null
    & reg.exe delete ('HKCR\' + $progId) /f 2>$null | Out-Null
    & reg.exe delete 'HKCU\Software\Classes\.apk' /f 2>$null | Out-Null
    & reg.exe delete ('HKCU\Software\Classes\' + $progId) /f 2>$null | Out-Null
    Log 'association removed.'
    return
}

if (-not (Test-Path $handlerSrc)) { throw ('handler script not found next to this script: ' + $handlerSrc) }

if (-not $AdbPath) {
    $onPath = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($onPath) { $AdbPath = $onPath.Source }
    else {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
            'D:\Android\sdk\platform-tools\adb.exe',
            'C:\Android\sdk\platform-tools\adb.exe'
        )
        $AdbPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}
if (-not $AdbPath -or -not (Test-Path $AdbPath)) { throw 'adb.exe not found - pass -AdbPath explicitly.' }
Log ('adb: ' + $AdbPath)

New-Item -ItemType Directory -Force -Path $HandlerDir | Out-Null
$handlerDst = Join-Path $HandlerDir 'wsa-install-apk.ps1'
Copy-Item $handlerSrc $handlerDst -Force
Log ('handler installed: ' + $handlerDst)

$cmdline = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $handlerDst + '" -AdbPath "' + $AdbPath + '" "%1"'

& reg.exe add 'HKCR\.apk' /ve /d $progId /f | Out-Null
& reg.exe add ('HKCR\' + $progId) /ve /d 'APK installer (Windows Subsystem for Android)' /f | Out-Null
& reg.exe add ('HKCR\' + $progId + '\shell\open\command') /ve /d $cmdline /f | Out-Null
& reg.exe add 'HKCU\Software\Classes\.apk' /ve /d $progId /f | Out-Null
& reg.exe add ('HKCU\Software\Classes\' + $progId) /ve /d 'APK installer (Windows Subsystem for Android)' /f | Out-Null
& reg.exe add ('HKCU\Software\Classes\' + $progId + '\shell\open\command') /ve /d $cmdline /f | Out-Null

Log 'association written. Verify with:  assoc .apk   /   ftype WSA.apk'
Log 'Test: open any .apk file (a console window shows install progress).'
