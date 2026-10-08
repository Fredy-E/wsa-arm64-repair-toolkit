# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `WsaClient.exe` crash-loops (`0xc0000409`; faulting module `ucrtbase.dll` @ `0x7c4dc`, or `WsaClient.exe` fault offsets in the `0x1EF44`/`0x1FAxx` family) | fail-fast error paths in the ARM64 client (see `WHAT-WE-FIXED.md`) | `python scripts/Patch-WsaClientArm64.py --apply <path>` — make sure the file is the pristine 5,749,248-byte build (restore from `.orig` first if needed) |
| Client crashes instantly right after a `settings.dat` edit | hand-written `DeveloperModeEnabled` value | stop all `Wsa*` processes, delete `settings.dat` + `settings.dat.LOG1/2` (or restore a clean copy), relaunch, then use `Enable-WsaDeveloperMode.ps1` |
| `adb connect` refused (port 58526 closed) | Developer mode off, or WSA not running | run `Enable-WsaDeveloperMode.ps1`; make sure the client is running (`!App`) |
| `adb devices` shows `unauthorized` | first-handshake state | wait a few seconds and re-run `adb devices`; WSA auto-authorizes localhost |
| Settings window opens but automation sees no elements | window is minimized (UIA tree stays empty) or the session is locked | restore the window (the script does this); run from an unlocked session |
| No USB devices inside Android apps | WSA has no USB passthrough | use Windows-native tooling, or a physical Android device with USB-OTG |
| `Add-AppxPackage -Register` fails on schema order | `<Capabilities>` requires all `Capability` elements before `DeviceCapability` | fix ordering; `Add-RestrictedAppUriHandlerCapability.ps1` inserts in a valid position and validates the XML |
| VM never starts (no `vmmemWSA`) | `VirtualMachinePlatform` feature disabled, or the first-run consent dialog is unanswered | enable the feature; start `!App` and answer the dialog |
| Patching refuses ("unsupported build") | file size/bytes do not match 2407.40000.4.0 ARM64 | you have a different build (or x64) — do not force it |
