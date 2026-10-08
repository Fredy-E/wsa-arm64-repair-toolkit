<#
.SYNOPSIS
  Add the restrictedAppUriHandlerHost capability to a WSA AppxManifest.xml.

.DESCRIPTION
  Sideloaded WSA packages can fail to re-register (or keep fail-fasting)
  without the restricted "restrictedAppUriHandlerHost" capability. This
  script inserts it in a schema-valid position (<Capabilities> requires all
  Capability elements before DeviceCapability), backs up the file, and
  validates the result as XML.

  Note: on some builds this is only one layer of the repair - the binary
  patch (Patch-WsaClientArm64.py) is the decisive fix. See docs/WHAT-WE-FIXED.md.

.PARAMETER ManifestPath
  Path to AppxManifest.xml (e.g. D:\WSA\install\AppxManifest.xml).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) { throw ('manifest not found: ' + $ManifestPath) }
if (Select-String -LiteralPath $ManifestPath -Pattern 'restrictedAppUriHandlerHost' -Quiet) {
    Write-Host 'capability already present - nothing to do.'
    return
}

$text = Get-Content -LiteralPath $ManifestPath -Raw
if ($text -notmatch 'xmlns:rescap') {
    throw 'manifest does not declare xmlns:rescap - aborting (the rescap: prefix must be declared first).'
}
$pattern = '(<Capabilities[^>]*>)'
if ($text -notmatch $pattern) { throw 'no <Capabilities> element found.' }

$backup = $ManifestPath + '.bak'
Copy-Item -LiteralPath $ManifestPath $backup -Force
Write-Host ('backup: ' + $backup)

$replacement = '$1' + [Environment]::NewLine + '    <rescap:Capability Name="restrictedAppUriHandlerHost" />'
$new = [regex]::Replace($text, $pattern, $replacement, 1)
Set-Content -LiteralPath $ManifestPath -Value $new -NoNewline

# validate
$null = [xml](Get-Content -LiteralPath $ManifestPath -Raw)
if (-not (Select-String -LiteralPath $ManifestPath -Pattern 'restrictedAppUriHandlerHost' -Quiet)) {
    throw 'insert failed.'
}
Write-Host 'capability added and XML validated.'
