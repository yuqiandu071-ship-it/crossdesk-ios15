#!/usr/bin/env python3
"""Make xmake's generated meson cross file usable for iOS targets.

xmake writes ``[host_machine] system = 'darwin'`` for iphoneos packages, which
makes meson's ``need_exe_wrapper()`` return False. meson then believes the
arm64 iOS test binaries can execute on the build host, runs them and gets them
killed with SIGKILL (return code -9). glib's gnulib probe interprets that as
"frexpl does not work" and aborts the configure step with:

    glib/gnulib/meson.build:319:2: ERROR: Problem encountered: frexpl() is
    missing or broken beyond repair, and we have nothing to replace it with

The fix is to emit ``[properties] needs_exe_wrapper = true`` into the cross
file for Apple device targets, so meson reports ``can_run_host_binaries()`` as
false instead of executing target binaries.
"""

from __future__ import annotations

import glob
import hashlib
import os
import re
import subprocess
import sys

MARKER = "CROSSDESK-NAF"
RELATIVE_MODULE = os.path.join("modules", "package", "tools", "meson.lua")

ANCHOR_RE = re.compile(
    r"(?P<indent>[ \t]*)file:print\(\"endian = 'little'\"\)\n"
)


def _run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "command failed (%d): %s\nstdout:\n%s\nstderr:\n%s"
            % (proc.returncode, " ".join(cmd), proc.stdout, proc.stderr)
        )
    return proc.stdout


def _program_dir(xmake: str) -> str | None:
    try:
        out = _run([xmake, "lua", "-c", "print(os.programdir())"])
    except Exception as exc:  # noqa: BLE001 - fall back to path probing
        print("programdir query failed: %s" % exc)
        return None
    for line in reversed(out.splitlines()):
        line = line.strip()
        if line.startswith("/") and os.path.isdir(line):
            return line
    return None


def _candidates(xmake: str) -> list[str]:
    found: list[str] = []
    override = os.environ.get("XMAKE_MESON_LUA")
    if override:
        found.append(override)

    roots: list[str] = []
    program_dir = _program_dir(xmake)
    if program_dir:
        roots.append(program_dir)

    real = os.path.realpath(xmake)
    roots.extend(
        [
            os.path.join(os.path.dirname(os.path.dirname(real)), "share", "xmake"),
            os.path.expanduser("~/.local/share/xmake"),
            os.path.expanduser("~/.xmake"),
            "/usr/local/share/xmake",
            "/opt/homebrew/share/xmake",
        ]
    )

    for root in roots:
        direct = os.path.join(root, RELATIVE_MODULE)
        if os.path.isfile(direct):
            found.append(direct)
        nested = os.path.join(root, "xmake", RELATIVE_MODULE)
        if os.path.isfile(nested):
            found.append(nested)

    if not found:
        pattern = os.path.join(
            os.path.expanduser("~"), "**", "modules", "package", "tools", "meson.lua"
        )
        found.extend(sorted(glob.glob(pattern, recursive=True))[:5])

    unique: list[str] = []
    for item in found:
        item = os.path.abspath(item)
        if item not in unique and os.path.isfile(item):
            unique.append(item)
    return unique


def patch(text: str) -> str:
    matches = list(ANCHOR_RE.finditer(text))
    if not matches:
        raise SystemExit(
            "no anchor found; xmake meson.lua layout changed, inspect the module manually"
        )
    # The iphoneos branch is the anchor occurrence immediately followed by the
    # android branch; fall back to the first occurrence otherwise.
    target = matches[0]
    for match in matches:
        tail = text[match.end(): match.end() + 200]
        if "package:is_plat(\"android\")" in tail:
            target = match
            break

    indent = target.group("indent")
    block = (
        indent + 'file:print("endian = \'little\'")\n'
        + indent + "-- " + MARKER + ": iOS cross builds must not run target binaries.\n"
        + indent + "if package:is_plat(\"iphoneos\", \"watchos\", \"appletvos\") then\n"
        + indent + '    file:print("[properties]")\n'
        + indent + '    file:print("needs_exe_wrapper = true")\n'
        + indent + "end\n"
    )
    return text[: target.start()] + block + text[target.end():]


def main() -> int:
    xmake = os.environ.get("XMAKE_BIN") or "xmake"
    candidates = _candidates(xmake)
    if not candidates:
        print("could not locate xmake's modules/package/tools/meson.lua", file=sys.stderr)
        return 2

    patched_any = False
    for path in candidates:
        with open(path, "r", encoding="utf-8") as handle:
            original = handle.read()
        if MARKER in original:
            print("already patched: %s" % path)
            patched_any = True
            continue
        if "needs_exe_wrapper = true" in original:
            print("unexpected pre-existing needs_exe_wrapper in %s" % path, file=sys.stderr)
            return 3
        updated = patch(original)
        if "needs_exe_wrapper = true" not in updated or MARKER not in updated:
            print("patch verification failed for %s" % path, file=sys.stderr)
            return 4
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(updated)
        digest = hashlib.sha256(updated.encode("utf-8")).hexdigest()
        print("patched %s (%d -> %d bytes, sha256=%s)" % (path, len(original), len(updated), digest))
        patched_any = True

    if not patched_any:
        return 5
    return 0


if __name__ == "__main__":
    sys.exit(main())
