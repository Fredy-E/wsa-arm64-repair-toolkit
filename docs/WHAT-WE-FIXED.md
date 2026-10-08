# What we fixed — WSA 2407.40000.4.0 (ARM64, Windows 11 25H2)

Repair notes from a Snapdragon X machine (Win11 25H2, build 26200) where a
sideloaded WSA 2407.40000.4.0 crash-looped before the Android VM could stay up.

## Symptom chain

1. `WsaClient.exe` started, the VM (`vmmemWSA`) booted, then the client died with
   `0xc0000409` (fail-fast) — repeatedly, within seconds.
2. Crash forensics (Windows Application log / WER) showed the faulting return
   address landing on a **fail-fast reporter function** at file offset `0x45B00`.
3. Community root cause for this era: on newer Windows builds the app's
   `AppUriHandlerRegistrationManager.UpdateAsync()` path fails with
   `E_ACCESSDENIED` and the client fail-fasts instead of continuing. (This is why
   community x64 fixes and a manifest capability fix exist.)

## Layers of the repair

### Layer 1 — manifest capability (necessary for re-registration, not sufficient)

The dev-package `AppxManifest.xml` needs the restricted capability:

```xml
<rescap:Capability Name="restrictedAppUriHandlerHost" />
```

See `scripts/Add-RestrictedAppUriHandlerCapability.ps1`. On our build this alone
did **not** stop the crash-loop — the binary still fail-fasts.

### Layer 2 — the ARM64 byte patches (the decisive fix)

`WsaClient.exe` (ARM64) contains a family of fail-fast thunks:

- 18 sites execute `brk #0xf000` (`00 00 3E D4`) — deliberate crash instructions
  on an error path. Patched to `ret` (`C0 03 5F D6`) so the error path returns.
- The **crash reporter function entry** at `0x45B00` (`sub sp, sp, #0x20` /
  `FF 83 00 D1`) — patched to `ret`, so calls into the reporter return immediately.

Full verified patch table (0-based file offsets, 19 × 4 bytes):

| # | Offset | Before | After | Note |
|---|--------|--------|-------|------|
| 1 | `0x1DA10` | `00003ed4` | `c0035fd6` | fail-fast trap → ret |
| 2–17 | `0x1EE24` … `0x1F0F4` (0x30 grid) | `00003ed4` | `c0035fd6` | fail-fast trap family → ret |
| 18 | `0x2C4C0` | `00003ed4` | `c0035fd6` | fail-fast trap → ret |
| 19 | `0x45B00` | `ff8300d1` | `c0035fd6` | crash reporter entry → ret (decisive) |

`scripts/Patch-WsaClientArm64.py` verifies size + every before-byte and refuses
any unknown build. Method: WER fault-offset forensics + Capstone disassembly of
the ARM64 code. The x64 client has its own, different patch set — see
`wesmar/WSAPatch`.

### Layer 3 — ARM64 Android images

Stock WSA ARM64 payloads can ship armv7-only Android images that do not boot on
Snapdragon X; community-repacked ARM64 images (snickler/WSA-Patched style) were
used in this repair. **This repository does not redistribute images** — supply
your own.

## Developer mode: what NOT to do

- **Never hand-write `DeveloperModeEnabled` into `settings.dat`** (the app's
  registry hive at
  `%LOCALAPPDATA%\Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\Settings\settings.dat`).
  Any externally-created value — raw `01` + 8 bytes, or even byte-identical
  values recovered from an older install — makes `WsaClient` abort instantly at
  launch (`ucrtbase.dll`, `0xc0000409` at `0x7c4dc`). Both variants were
  verified to crash.
- The only working way is the settings UI toggle.
  `Enable-WsaDeveloperMode.ps1` drives it via UI Automation:
  - The settings window ("Windows Subsystem for Android™") is hosted by
    `ApplicationFrameHost`; **if minimized, its UIA tree is empty** — restore it
    first (`ShowWindow` `SW_RESTORE`), then the tree appears (~43 nodes).
  - Toggle = `Button` named
    `Developer mode. Devices on the same private network can access the Subsystem.`
    under *Advanced settings*; invoke via `TogglePattern`.
  - Once on, adb port `58526` opens; the first `adb connect` may briefly show
    `unauthorized`, then authorizes itself to `device`.

## APK double-click → installs into WSA

Sideloaded builds register **no `.apk` file handler** (verified: no
`fileTypeAssociation` in the manifest, no `HKCR\.apk` entry). The toolkit
installs one: a ProgID (`WSA.apk`) whose open command runs `wsa-install-apk.ps1`,
which connects adb, auto-starts WSA if needed, and `adb install -r`s the file.

Tested end-to-end: opening an `.apk` re-installed the package (verified by the
package's `lastUpdateTime` changing). Note: `AssocQueryString` can still report
`ERROR_NO_ASSOCIATION` in some contexts even though the association works —
trust the live test, not the query.

## Final state (verified)

- Zero crashes across long runs after the reporter patch; client + VM stable.
- Developer mode ON via the settings UI; `adb devices` → `127.0.0.1:58526 device`.
- Two test apps installed and launched (screenshots in `docs/screenshots/`).
- `.apk` association installed and exercised.
