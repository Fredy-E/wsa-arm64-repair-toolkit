<#
.SYNOPSIS
  Enable Developer mode in Windows Subsystem for Android via UI Automation.

.DESCRIPTION
  The ONLY safe way to enable WSA Developer mode. Hand-editing the
  DeveloperModeEnabled value in the app's settings.dat hive makes WsaClient
  abort instantly at launch (ucrtbase.dll 0xc0000409 at 0x7c4dc) - do not do it.

  This script opens the WSA settings window, restores it if minimized
  (a minimized ApplicationFrameHost window exposes an empty UI Automation
  tree), flips the "Developer mode" toggle, verifies the state, then waits
  for the adb port to open.

  Run from an UNLOCKED, interactive session.

.PARAMETER SettingsAumid
  AppUserModelId of the WSA settings app.
.PARAMETER Port
  adb port to wait for (default 58526).
.PARAMETER TimeoutSeconds
  How long to wait for the adb port after toggling.
#>
[CmdletBinding()]
param(
    [string]$SettingsAumid = 'MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe!SettingsApp',
    [int]$Port = 58526,
    [int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
function Log($m) { Write-Host (('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)) }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
'@

Log 'opening WSA settings window'
Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:appsFolder\' + $SettingsAumid)

$auto = [System.Windows.Automation.AutomationElement]::RootElement
$winCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window)

$target = $null
for ($i = 0; $i -lt 10 -and -not $target; $i++) {
    Start-Sleep -Seconds 5
    $wins = $auto.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)
    foreach ($w in $wins) {
        if ($w.Current.Name -match 'Subsystem for Android') { $target = $w; break }
    }
}
if (-not $target) { throw 'WSA settings window not found.' }

$hwnd = [IntPtr]$target.Current.NativeWindowHandle
if ([Win32]::IsIconic($hwnd)) {
    Log 'settings window is minimized - restoring (UIA tree is empty while minimized)'
    [void][Win32]::ShowWindow($hwnd, 9)   # SW_RESTORE
    [void][Win32]::SetForegroundWindow($hwnd)
    Start-Sleep -Seconds 2
}

$btn = $null
$all = $target.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
foreach ($e in $all) {
    if ($e.Current.Name -match '^Developer mode\.') { $btn = $e; break }
}
if (-not $btn) { throw 'Developer mode toggle not found in the settings window (is the window fully loaded?).' }

$toggle = $null
if (-not $btn.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$toggle)) {
    throw 'Developer mode control does not support TogglePattern.'
}
Log ('Developer mode toggle state: ' + $toggle.Current.ToggleState)
if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
    $toggle.Toggle()
    Start-Sleep -Seconds 3
    Log ('state after toggle: ' + $toggle.Current.ToggleState)
} else {
    Log 'already ON'
}

Log ('waiting for adb port ' + $Port + ' (WSA may take a minute to start or restart the subsystem)')
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$open = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $open = (Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet)
    } catch { $open = $false }
    if ($open) { break }
}
if ($open) {
    Log ('adb port ' + $Port + ' is OPEN - Developer mode is active. Connect with: adb connect 127.0.0.1:' + $Port)
} else {
    Log ('adb port ' + $Port + ' did not open within ' + $TimeoutSeconds + 's. Start the WSA client window (the !App shell target) and re-run, or check Show-WsaStatus.ps1.')
    exit 1
}
