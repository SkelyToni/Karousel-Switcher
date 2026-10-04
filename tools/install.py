#!/usr/bin/env python3
"""Install the local ScrollTab switcher; optionally select it in user settings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = {
    "SwitchingMode": "0", "DesktopMode": "1", "ApplicationsMode": "0",
    "OrderMinimizedMode": "0", "ShowDesktopMode": "0", "ShowTabBox": "true",
    "DelayTime": "0",
    "HighlightWindows": "false",
}


def read_values(text):
    result = {}
    group = None
    for line in text.splitlines():
        if line.startswith("["):
            group = line.strip()
        elif group == "[TabBox]" and "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def update_values(text, values):
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.strip() == "[TabBox]"]
    if len(starts) > 1:
        raise ValueError("Multiple [TabBox] groups; restore or consolidate them first")
    if not starts:
        if not any(value is not None for value in values.values()):
            return text
        if text and not text.endswith("\n"):
            lines.append("\n")
        lines.extend(["\n", "[TabBox]\n"])
        start, end = len(lines), len(lines)
    else:
        start = starts[0] + 1
        end = next((i for i in range(start, len(lines)) if lines[i].startswith("[")), len(lines))
    section = []
    seen = set()
    for line in lines[start:end]:
        match = re.match(r"^([^#;=]+)=", line)
        key = match.group(1).strip() if match else None
        if key not in values:
            section.append(line)
        elif key not in seen:
            seen.add(key)
            if values[key] is not None:
                section.append(key + "=" + values[key] + "\n")
    for key, value in values.items():
        if key not in seen and value is not None:
            section.append(key + "=" + value + "\n")
    return "".join(lines[:start] + section + lines[end:])


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".scrolltab-tmp")
    temporary.write_text(text)
    temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o600)
    temporary.replace(path)


def package_id():
    digest = hashlib.sha256()
    for path in sorted((ROOT / "switcher").rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(ROOT / "switcher")).encode())
            digest.update(path.read_bytes())
    return "scrolltab-" + digest.hexdigest()[:12]


def reconfigure():
    qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
    if not qdbus:
        raise RuntimeError("Settings saved, but qdbus is missing. Log out and back in to reload KWin.")
    subprocess.run([qdbus, "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "uninstall"])
    parser.add_argument("--data-home", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    parser.add_argument("--config-home", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")))
    parser.add_argument("--configure", action="store_true", help="Select ScrollTab and save previous user settings")
    parser.add_argument("--activate", action="store_true", help="Configure and reconfigure the running KWin")
    args = parser.parse_args()
    directory = args.data_home.resolve() / "kwin/tabbox"
    config = args.config_home.resolve() / "kwinrc"
    manifest_path = directory / ".scrolltab-install.json"
    state = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    text = config.read_text() if config.exists() else ""
    values = read_values(text)
    if args.action == "uninstall":
        if not state:
            raise ValueError("ScrollTab is not installed here")
        if state.get("config"):
            if state["config"] != str(config):
                raise ValueError("Use the config-home used for installation")
            changed = [key for key, value in state["installed"].items() if values.get(key) != value]
            if changed:
                raise ValueError("These settings changed after installation; refusing to overwrite them: " + ", ".join(changed))
            atomic_write(config, update_values(text, state["original"]))
        # Keep packages for rollback and avoid deleting a cached active layout.
        for name in state.get("packages", []):
            metadata = directory / name / "metadata.json"
            if metadata.exists():
                metadata.rename(metadata.with_suffix(".json.retired"))
        state["restored"] = True
        atomic_write(manifest_path, json.dumps(state, indent=2) + "\n")
        if args.activate:
            reconfigure()
        print("Previous switcher settings restored. Package files retained for rollback.")
        return

    plugin_id = package_id()
    installed = SETTINGS | {"LayoutName": plugin_id}
    if args.configure or args.activate:
        if state.get("restored"):
            state = {"packages": state.get("packages", [])}
        if "original" not in state:
            state["original"] = {key: values.get(key) for key in installed}
            state["config"] = str(config)
            atomic_write(directory / ".scrolltab-original-kwinrc", text)
        elif state["config"] != str(config):
            raise ValueError("Use the config-home used for the previous installation")
        state["installed"] = installed

    package = directory / plugin_id
    shutil.copytree(ROOT / "switcher", package, dirs_exist_ok=True)
    metadata = json.loads((package / "metadata.json").read_text())
    metadata["KPlugin"]["Id"] = plugin_id
    (package / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for name in state.get("packages", []):
        old = directory / name / "metadata.json"
        if name != plugin_id and old.exists():
            old.rename(old.with_suffix(".json.retired"))
    state["packages"] = sorted(set(state.get("packages", [])) | {plugin_id})
    state["package"] = plugin_id
    if args.configure or args.activate:
        atomic_write(config, update_values(text, installed))
    atomic_write(manifest_path, json.dumps(state, indent=2) + "\n")
    if args.activate:
        reconfigure()
    print(f"Installed {package}")
    if not args.configure and not args.activate:
        print("Run again with --activate to select ScrollTab and reload KWin. No sudo is needed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
