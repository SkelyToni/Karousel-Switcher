#!/usr/bin/env python3
"""Verify real Alt+Tab input in an isolated, stock virtual KWin session."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Compiled tools/send_keys.c input driver")
    parser.add_argument("--qml", default="qml")
    parser.add_argument("--kwin", default="kwin_wayland")
    parser.add_argument("--geometry-base", type=Path, help="Stage Geometry Change with smooth motion adaptation")
    parser.add_argument("--extra-windows", type=int, default=0, help="Add windows to exercise crowded-strip behavior")
    parser.add_argument("--log", type=Path, default=Path("/tmp/scrolltab-smoke.log"))
    args = parser.parse_args()
    qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
    if not qdbus:
        raise RuntimeError("qdbus is required")
    processes = []
    with tempfile.TemporaryDirectory(prefix="scrolltab-smoke-") as directory:
        temp = Path(directory)
        env = os.environ.copy()
        for name, suffix in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                             ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "runtime")]:
            path = temp / suffix
            path.mkdir(mode=0o700)
            env[name] = str(path)
        env.update(WAYLAND_DISPLAY="scrolltab-test", SCROLLTAB_TEST_SESSION="1",
                   KWIN_COMPOSE="O2", LIBGL_ALWAYS_SOFTWARE="1", QML_DISABLE_DISK_CACHE="1",
                   QT_FORCE_STDERR_LOGGING="1", QT_LOGGING_TO_CONSOLE="1",
                   KWIN_WAYLAND_NO_PERMISSION_CHECKS="1", QT_NO_XDG_DESKTOP_PORTAL="1")
        env.pop("DISPLAY", None)
        applications = temp / "data/applications"
        applications.mkdir()
        (applications / "scrolltab-test-keys.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=ScrollTab test input\n"
            f"Exec={args.input.resolve()}\nX-KDE-Wayland-Interfaces=org_kde_kwin_fake_input;\n")
        (temp / "config/kwinrc").write_text("[Desktops]\nNumber=2\nRows=1\n[TabBox]\nHighlightWindows=false\n")
        if args.geometry_base:
            geometry = temp / "data/kwin/effects/kwin4_effect_geometry_change"
            shutil.copytree(args.geometry_base, geometry)
            shutil.copyfile(ROOT / "geometry-change/main.js", geometry / "contents/code/main.js")
            with (temp / "config/kwinrc").open("a") as config:
                config.write("\n[Plugins]\nkwin4_effect_geometry_changeEnabled=true\n")
        subprocess.run([sys.executable, str(ROOT / "tools/install.py"), "install", "--configure",
                        "--data-home", str(temp / "data"), "--config-home", str(temp / "config")],
                       check=True, capture_output=True)
        state = json.loads((temp / "data/kwin/tabbox/.scrolltab-install.json").read_text())
        controller = temp / "data/kwin/tabbox" / state["package"] / "contents/ui/SpatialController.qml"
        controller.write_text(controller.read_text().replace("        initialized = true;",
            '        initialized = true; console.log("SCROLLTAB-OPEN", rows.map(function(r){return r.caption;}).join(","), selectedRow);'))
        popup = controller.parent / "main.qml"
        popup.write_text(popup.read_text().replace("        location: PlasmaCore.Types.Floating",
            '''            property Connections renderProbe: Connections {
                target: popup
                function onFrameSwapped() {
                    console.log("SCROLLTAB-RENDERED", popup.visible, spatial.selectedRow,
                        KWin.Workspace.activeWindow ? KWin.Workspace.activeWindow.caption : "");
                }
            }
            property Timer popupProbe: Timer {
                interval: 70; running: tabBox.visible; repeat: true
                onTriggered: {
                    console.log("SCROLLTAB-HELD", parent.visible, spatial.selectedRow,
                        KWin.Workspace.activeWindow ? KWin.Workspace.activeWindow.caption : "");
                    var view = thumbnailGridView;
                    var item = view.currentItem;
                    console.log("SCROLLTAB-ROW", view.orientation === ListView.Horizontal &&
                        view.height <= view.cellHeight + 1 && item && Math.abs(item.y) < 1,
                        view.contentWidth > view.width,
                        item && item.x >= view.contentX - 1 &&
                            item.x + item.width <= view.contentX + view.width + 1,
                        spatial.rows[spatial.selectedRow].caption);
                    var loaders = [];
                    function collect(item) {
                        if (item.objectName === "scrolltabThumbnailLoader") loaders.push(item);
                        Array.from(item.children || []).forEach(collect);
                    }
                    collect(view.contentItem);
                    var selectedReady = false;
                    if (item) {
                        var selectedLoaders = [];
                        function ready(child) {
                            if (child.objectName === "scrolltabThumbnailLoader" && child.status === Loader.Ready)
                                selectedReady = true;
                            if (child.objectName === "scrolltabThumbnailSnapshot" && child.status === Image.Ready)
                                selectedReady = true;
                            Array.from(child.children || []).forEach(ready);
                        }
                        ready(item);
                    }
                    console.log("SCROLLTAB-THUMBNAILS", loaders.filter(function(l){return l.active;}).length,
                        spatial.rows.length, selectedReady);
                }
            }
        location: PlasmaCore.Types.Floating'''))
        with args.log.open("w") as log:
            def dbus(*arguments):
                return subprocess.run([qdbus, *arguments], env=env, capture_output=True,
                                      text=True, check=True, timeout=15).stdout.strip()
            script_number = 0
            def script(text):
                nonlocal script_number
                script_number += 1
                path = temp / f"probe-{script_number}.js"
                path.write_text(text)
                dbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", str(path), f"scrolltab-probe-{script_number}")
                dbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")
            try:
                processes.append(subprocess.Popen([args.kwin, "--virtual", "--width", "1280", "--height", "800",
                                                    "--no-lockscreen", "--socket", "scrolltab-test"],
                                                   env=env, stdout=log, stderr=log))
                deadline = time.monotonic() + 12
                while not (temp / "runtime/scrolltab-test").exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if not (temp / "runtime/scrolltab-test").exists():
                    raise RuntimeError("Virtual KWin failed to start")
                extras = [f"Extra{number}" for number in range(args.extra_windows)]
                for name in ["Right", "Lower", "Left", "Middle", "Other", "Sticky"] + extras:
                    path = temp / (name + ".qml")
                    path.write_text('import QtQuick\nimport QtQuick.Window\nWindow { visible: true; width: 200; height: 150; title: "ScrollTab ' + name + '"; color: "#334466" }\n')
                    processes.append(subprocess.Popen([args.qml, "-platform", "wayland", str(path)],
                                                       env=env, stdout=log, stderr=log))
                    time.sleep(0.15)
                time.sleep(1)
                if args.geometry_base and dbus("org.kde.KWin", "/Effects",
                        "org.kde.kwin.Effects.isEffectLoaded", "kwin4_effect_geometry_change") != "true":
                    raise RuntimeError("Geometry Change failed to load")
                fixture = temp / "fixture.qml"
                fixture.write_text('''import QtQuick
import org.kde.kwin as KWin
QtObject {
Component.onCompleted: {
var positions = {"Right":[2600,100], "Lower":[400,350], "Left":[-2000,100], "Middle":[400,100], "Other":[600,100], "Sticky":[1600,100]};
Array.from(KWin.Workspace.windows).forEach(function(w) {
    var name = w.caption.replace("ScrollTab ", "");
    if (!positions[name]) return;
    w.frameGeometry = Qt.rect(positions[name][0], positions[name][1], 200, 150);
    if (name === "Other") w.desktops = [KWin.Workspace.desktops[1]];
    if (name === "Sticky") w.onAllDesktops = true;
});
KWin.Workspace.currentDesktop = KWin.Workspace.desktops[0];
console.log("SCROLLTAB-CLIENTS", Array.from(KWin.Workspace.windows).filter(function(w){return w.caption.indexOf("ScrollTab ") === 0;}).length);
}
}''')
                if extras:
                    fixture.write_text(fixture.read_text().replace(
                        'Array.from(KWin.Workspace.windows).forEach(function(w) {',
                        'Object.assign(positions, ' + json.dumps({name: [4000 + i * 400, 100]
                            for i, name in enumerate(extras)}) + ');\n' +
                        'Array.from(KWin.Workspace.windows).forEach(function(w) {', 1))
                if args.geometry_base:
                    fixture.write_text(fixture.read_text().replace("QtObject {", '''QtObject {
property Timer motionProbe: Timer {
    interval: 30; running: true; repeat: true
    property int ticks: 0
    onTriggered: {
        ticks++;
        Array.from(KWin.Workspace.windows).forEach(function(w) {
            if (w.caption.indexOf("ScrollTab ") !== 0) return;
            var frame = w.frameGeometry;
            w.frameGeometry = Qt.rect(frame.x + (ticks === 1 ? 30 : -30), frame.y, frame.width, frame.height);
        });
        if (ticks === 2) { stop(); console.log("SCROLLTAB-GEOMETRY-INTERRUPTED"); }
    }
}
'''))
                dbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadDeclarativeScript", str(fixture), "scrolltab-fixture")
                dbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")
                time.sleep(0.1)
                # Spatial order of the current-desktop windows; Middle starts
                # active, and stepping wraps around both ends.
                order = ["Left", "Middle", "Lower", "Sticky", "Right"] + extras
                def target(steps):
                    return order[(order.index("Middle") + steps) % len(order)]
                cases = [(1, 0, False), (-1, 0, False), (1, 350, False), (2, 150, False),
                         (3, 150, False), (4, 150, False), (-2, 150, False), (2, 150, True),
                         (20, 150, False), (-20, 150, False)]
                cases = [(steps, hold, cancel, "Middle" if cancel else target(steps))
                         for steps, hold, cancel in cases]
                for number, (steps, hold, cancel, expected) in enumerate(cases):
                    script('workspace.activeWindow = workspace.windowList().find(function(w){return w.caption === "ScrollTab Middle";});')
                    time.sleep(0.05)
                    command = [str(args.input.resolve()), str(steps), str(hold)]
                    if cancel:
                        command.append("cancel")
                    subprocess.run(command, env=env, check=True, stdout=log, stderr=log, timeout=5)
                    time.sleep(0.1)
                    script(f'print("SCROLLTAB-CHECK {number}", workspace.activeWindow.caption === "ScrollTab {expected}", workspace.activeWindow.caption);')
                    time.sleep(0.05)
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                for process in processes:
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    output = args.log.read_text()
    if f"SCROLLTAB-CLIENTS {6 + args.extra_windows}" not in output:
        raise RuntimeError(f"Test clients missing; inspect {args.log}")
    for number in range(10):
        if f"SCROLLTAB-CHECK {number} true" not in output:
            raise RuntimeError(f"Alt+Tab test {number} failed; inspect {args.log}")
    if "SCROLLTAB-OPEN" not in output:
        raise RuntimeError(f"ScrollTab did not open; inspect {args.log}")
    if "SCROLLTAB-RENDERED true" not in output:
        raise RuntimeError(f"ScrollTab popup did not render; inspect {args.log}")
    if "SCROLLTAB-HELD false" in output:
        raise RuntimeError(f"Popup was hidden while Alt was held (re-created during switching); inspect {args.log}")
    if "SCROLLTAB-HELD true 2 ScrollTab Lower" not in output:
        raise RuntimeError(f"Popup or live focus missing while Alt is held; inspect {args.log}")
    if "SCROLLTAB-ROW true true true ScrollTab Right" not in output:
        raise RuntimeError(f"Single-row overflow or selected-item visibility failed; inspect {args.log}")
    if args.extra_windows:
        probes = [line.split("SCROLLTAB-THUMBNAILS ", 1)[1].split() for line in output.splitlines()
            if "SCROLLTAB-THUMBNAILS " in line]
        if not any(len(probe) == 3 and int(probe[0]) < int(probe[1]) and probe[2] == "true" for probe in probes):
            raise RuntimeError(f"Thumbnail preloading/virtualization failed; inspect {args.log}")
    if args.geometry_base and "SCROLLTAB-GEOMETRY-INTERRUPTED" not in output:
        raise RuntimeError(f"Geometry interruption probe did not run; inspect {args.log}")
    errors = [line for line in output.splitlines() if any(name in line.lower() for name in ["scrolltab", "geometry_change"]) and
              any(token in line for token in ["TypeError", "ReferenceError", "is not a type", "Cannot assign", "Unable to assign"])]
    if errors:
        raise RuntimeError("QML errors: " + "\n".join(errors[:12]))
    print("Virtual stock KWin smoke passed: quick taps, held Alt, forward/reverse, wrap-around, current desktop, all-desktops windows, and Escape. Log: " + str(args.log))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
