#!/usr/bin/env python3
"""Apply or restore the Geometry Change 1.5 smooth retargeting adaptation."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = "ae1e227fd975372668658aef06ba242e1003257a6edf4e7adbd632e45052e1f1"
PREVIOUS = "82b6c125c608316626a83fa69176bc5d710ab2f1e96e55e1ee8688e13829043f"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "restore"])
    parser.add_argument("--data-home", type=Path, default=Path(os.environ.get(
        "XDG_DATA_HOME", Path.home() / ".local/share")))
    parser.add_argument("--activate", action="store_true")
    args = parser.parse_args()
    package = args.data_home / "kwin/effects/kwin4_effect_geometry_change"
    target = package / "contents/code/main.js"
    backup = package / ".scrolltab-original-main.js"
    installed = package / ".scrolltab-installed-main.sha256"
    replacement = (ROOT / "geometry-change/main.js").read_bytes()
    current = target.read_bytes()
    supported = {ORIGINAL, PREVIOUS, digest(replacement)}
    if installed.exists():
        supported.add(installed.read_text().strip())
    if args.action == "install":
        if digest(current) not in supported:
            raise SystemExit("Geometry Change differs from supported version 1.5; no files changed.")
        if not backup.exists():
            if digest(current) != ORIGINAL:
                raise SystemExit("Original backup missing; no files changed.")
            backup.write_bytes(current)
        if digest(backup.read_bytes()) != ORIGINAL:
            raise SystemExit("Original backup differs from supported version; no files changed.")
        data = replacement
    else:
        if digest(current) not in supported:
            raise SystemExit("Geometry Change was independently edited; no files changed.")
        data = backup.read_bytes()
        if digest(data) != ORIGINAL:
            raise SystemExit("Original backup differs from supported version; no files changed.")
    temporary = target.with_suffix(".js.scrolltab-tmp")
    temporary.write_bytes(data)
    temporary.replace(target)
    installed.write_text(digest(data) + "\n")
    if args.activate:
        qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
        if not qdbus:
            raise SystemExit("Source updated; qdbus is required to reload the effect.")
        for method in ("unloadEffect", "loadEffect"):
            result = subprocess.run([qdbus, "org.kde.KWin", "/Effects",
                f"org.kde.kwin.Effects.{method}", "kwin4_effect_geometry_change"],
                check=True, capture_output=True, text=True)
            if method == "loadEffect" and result.stdout.strip() == "false":
                raise SystemExit("Source updated but effect reload failed; original backup retained.")
    print(f"Geometry Change {'updated' if args.action == 'install' else 'restored'}: {target}")


if __name__ == "__main__":
    main()
