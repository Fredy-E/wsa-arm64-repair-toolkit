#!/usr/bin/env python3
"""Tests for scripts/Patch-WsaClientArm64.py using a synthetic buffer (no real binaries needed).

Run:  python tests/test_patcher.py
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PATCHER_PATH = HERE.parent / "scripts" / "Patch-WsaClientArm64.py"

spec = importlib.util.spec_from_file_location("patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)

failures = []


def check(name, cond):
    status = "ok" if cond else "FAIL"
    print(f"[{status}] {name}")
    if not cond:
        failures.append(name)


def make_pristine():
    """Synthetic image: zeros + every expected 'before' byte at its offset."""
    buf = bytearray(patcher.SUPPORTED_SIZE)
    for off, before, _after, _note in patcher.PATCHES:
        buf[off:off + 4] = before
    return buf


# 1. table sanity
check("19 patches defined", len(patcher.PATCHES) == 19)
check("offsets within file",
      all(0 < off < patcher.SUPPORTED_SIZE - 4 for off, _, _, _ in patcher.PATCHES))
check("patch lengths are 4 bytes",
      all(len(b) == 4 and len(a) == 4 for _, b, a, _ in patcher.PATCHES))
check("no duplicate offsets",
      len({off for off, _, _, _ in patcher.PATCHES}) == len(patcher.PATCHES))

# 2. classify pristine
buf = make_pristine()
state, _detail = patcher.classify(bytes(buf))
check("pristine classified", state == "pristine")

# 3. apply all
applied = patcher.apply_patches(buf)
check("all patches applied", len(applied) == 19)
state2, _ = patcher.classify(bytes(buf))
check("now classified patched", state2 == "patched")

# 4. idempotent re-apply
applied2 = patcher.apply_patches(buf)
check("re-apply is a no-op", applied2 == [])

# 5. wrong size refused
state3, _ = patcher.classify(b"\x00" * 1000)
check("wrong size -> unknown", state3 == "unknown")

# 6. corrupted byte refused
bad = make_pristine()
bad[patcher.PATCHES[0][0]] ^= 0xFF
state4, _ = patcher.classify(bytes(bad))
check("corrupted byte -> unknown", state4 == "unknown")

# 7. mixed state refused
mixed = make_pristine()
off0, _b, after0, _n = patcher.PATCHES[0]
mixed[off0:off0 + 4] = after0
state5, _ = patcher.classify(bytes(mixed))
check("mixed state -> unknown", state5 == "unknown")

# 8. every patch targets ret; exactly 18 brk traps
ret = bytes.fromhex("c0035fd6")
brk = bytes.fromhex("00003ed4")
check("all patches target ret", all(a == ret for _, _, a, _ in patcher.PATCHES))
check("18 brk traps + 1 reporter entry",
      sum(1 for _, b, _, _ in patcher.PATCHES if b == brk) == 18)

if failures:
    print(f"\n{len(failures)} FAILURES")
    sys.exit(1)
print("\nall tests passed")
