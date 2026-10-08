#!/usr/bin/env python3
"""Verify and apply the ARM64 crash-fix byte patches to a local copy of WsaClient.exe.

Supported build: WSA 2407.40000.4.0 (ARM64), WsaClient.exe, 5,749,248 bytes.
No Microsoft binaries are redistributed; this script edits a file you supply.

Usage:
  python Patch-WsaClientArm64.py --check <path-to-WsaClient.exe>
  python Patch-WsaClientArm64.py --apply <path-to-WsaClient.exe> [--out <patched path>]

--check : verify the file matches the supported build and report patch status (no writes)
--apply : back up to <path>.orig (if absent) and apply all 19 patches in place,
          or write to --out when given, leaving the input untouched.

Exit codes: 0 ok / already patched, 1 verification failed, 2 usage or I/O error.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

SUPPORTED_VERSION = "2407.40000.4.0"
SUPPORTED_SIZE = 5_749_248
RET = bytes.fromhex("c0035fd6")  # ret
BRK = bytes.fromhex("00003ed4")  # brk #0xf000

# (offset, before, after, note) - 0-based file offsets, verified against the
# supported build. Size and every before-byte are checked before any write.
PATCHES = [
    (0x1DA10, BRK, RET, "fail-fast trap -> ret"),
    (0x1EE24, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EE54, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EE84, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EEB4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EEE4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EF14, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EF44, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EF74, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EFA4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1EFD4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F004, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F034, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F064, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F094, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F0C4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x1F0F4, BRK, RET, "fail-fast trap -> ret (thunk grid)"),
    (0x2C4C0, BRK, RET, "fail-fast trap -> ret"),
    (0x45B00, bytes.fromhex("ff8300d1"), RET,
     "crash reporter entry (sub sp,sp,#0x20) -> ret (decisive fix)"),
]


def classify(data: bytes):
    """Return (state, detail) where state is 'pristine', 'patched' or 'unknown'."""
    if len(data) != SUPPORTED_SIZE:
        return "unknown", f"size {len(data)} != supported {SUPPORTED_SIZE}"
    states = []
    for off, before, after, _note in PATCHES:
        cur = data[off:off + 4]
        if cur == before:
            states.append("pristine")
        elif cur == after:
            states.append("patched")
        else:
            return "unknown", (
                f"bytes at 0x{off:X} are {cur.hex()} "
                f"(expected {before.hex()} or {after.hex()})"
            )
    if all(s == "pristine" for s in states):
        return "pristine", f"{len(PATCHES)} patches pending"
    if all(s == "patched" for s in states):
        return "patched", "all patches already applied"
    return "unknown", "mixed state (partially patched?) - restore from .orig before patching"


def apply_patches(data: bytearray):
    """Apply all patches to a mutable buffer; returns list of (offset, note) applied."""
    applied = []
    for off, before, after, note in PATCHES:
        cur = bytes(data[off:off + 4])
        if cur == before:
            data[off:off + 4] = after
            applied.append((off, note))
        elif cur == after:
            pass  # already patched
        else:
            raise ValueError(f"bytes at 0x{off:X} changed during patching")
    return applied


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Patch WsaClient.exe (WSA 2407.40000.4.0 ARM64) - edits your local copy only.")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", metavar="EXE", help="verify build + report patch state (no writes)")
    g.add_argument("--apply", metavar="EXE", help="back up to .orig (if needed) and patch")
    ap.add_argument("--out", metavar="PATH",
                    help="with --apply: write the patched copy here instead of patching in place")
    args = ap.parse_args(argv)

    target = Path(args.check or args.apply)
    if not target.is_file():
        print(f"error: not a file: {target}", file=sys.stderr)
        return 2

    data = target.read_bytes()
    state, detail = classify(data)
    print(f"file:   {target}")
    print(f"size:   {len(data)} bytes")
    print(f"state:  {state} ({detail})")

    if state == "unknown":
        print("refusing: unsupported build - this toolkit only patches WSA 2407.40000.4.0 ARM64.",
              file=sys.stderr)
        return 1
    if args.check:
        return 0
    if state == "patched":
        print("nothing to do - all 19 patches already applied.")
        return 0

    if args.out:
        buf = bytearray(data)
        applied = apply_patches(buf)
        Path(args.out).write_bytes(bytes(buf))
        print(f"wrote patched copy: {args.out} ({len(applied)} patches applied)")
        return 0

    backup = Path(str(target) + ".orig")
    if not backup.exists():
        shutil.copy2(target, backup)
        print(f"backup written: {backup}")
    else:
        print(f"backup already exists (kept): {backup}")

    buf = bytearray(data)
    applied = apply_patches(buf)
    target.write_bytes(bytes(buf))
    print(f"patched in place: {target} ({len(applied)} patches applied)")

    state2, detail2 = classify(target.read_bytes())
    print(f"post-check: {state2} ({detail2})")
    return 0 if state2 == "patched" else 1


if __name__ == "__main__":
    sys.exit(main())
