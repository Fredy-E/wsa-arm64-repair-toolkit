<#
.SYNOPSIS
  Quick status for Windows Subsystem for Android: processes, adb port, recent crashes.

.PARAMETER Port
  adb port to probe (default 58526).
.PARAMETER CrashLookbackMinutes
  How far back to count WsaClient crash events (default 60).
#>
[CmdletBinding()]
param(
    [int]$Port = 58526,
    [int]$CrashLookbackMinutes = 60
)
$ErrorActionPreference = 'Continue'

Write-Host '== processes =='
Get-Process | Where-Object { $_.Name -match 'Wsa|vmmem' } |
    Select-Object Name, Id | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

Write-Host ('== adb port ' + $Port + ' ==')
$open = $false
try {
    $open = (Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet)
} catch { $open = $false }
Write-Host ('open: ' + $open)

Write-Host ('== WsaClient crash events (last ' + $CrashLookbackMinutes + ' min) ==')
$ev = @(Get-WinEvent -LogName Application -MaxEvents 400 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -eq 'Application Error' -and
        ('' + $_.Message) -match 'WsaClient' -and
        $_.TimeCreated -gt (Get-Date).AddMinutes(-$CrashLookbackMinutes)
    })
Write-Host ('count: ' + $ev.Count)
foreach ($e in ($ev | Select-Object -First 5)) {
    $off = ([regex]::Match($e.Message, 'Fault offset: 0x([0-9a-f]+)').Groups[1].Value)
    $mod = ([regex]::Match($e.Message, 'Faulting module name: ([^,]+)').Groups[1].Value)
    Write-Host ('  ' + $e.TimeCreated.ToString('HH:mm:ss') + '  module=' + $mod + ' offset=0x' + $off)
}
