# ScrollTab

A **local KDE Alt+Tab switcher** showing the current desktop's windows from left
to right. It reuses KDE's Thumbnail Grid QML for the popup, thumbnails, icons,
selection highlight, captions, and close buttons. It does **not** patch KWin or
require a NixOS configuration change, system rebuild, or sudo.

KDE retains keyboard handling and activation when you release Alt. Each step
also focuses the selected window immediately, so Karousel scrolls it into view
while Alt is held. Escape restores the original focus. ScrollTab maps KDE's
selected window to its own spatial list, so repeated Alt+Tab follows the same
order shown in the popup.

## Install

From this directory, with Python 3 available:

```sh
python3 tools/install.py install --activate
```

The installer copies the package to `~/.local/share/kwin/tabbox/`, selects it in
your **user** `~/.config/kwinrc`, and asks KWin to reconfigure. Previous values
are saved for restoration. It changes only the main switcher's layout, filter,
and ordering settings; your shortcut bindings remain the same.

To copy the package without changing settings, omit `--activate`. To stage an
installation for testing, use `--data-home PATH --config-home PATH --configure`.

If Python isn't in your NixOS PATH, `nix-shell -p python3 --run
'python3 tools/install.py install --activate'` supplies the installer runtime.
This is an ordinary temporary development environment, not a system rebuild.

## Controls and behavior

- **Alt+Tab** moves right; **Alt+Shift+Tab** moves left. Navigation stops at
  the first and last window, without wrapping around.
  With exactly two windows, either shortcut toggles between them: KWin's
  selection index cannot distinguish forward from reverse in this case.
- Each step focuses the selected window and lets Karousel scroll to it.
  Release **Alt** to keep that window; **Escape** restores the starting window.
- Thumbnails stay in one horizontal row. The row scrolls to keep the selected
  window visible when there are more windows than fit on screen.
- Arrow keys navigate the thumbnail row; Home/End select its first/last entry.
- Click a thumbnail to activate; use its close button to close that window.
- Windows are sorted by frame x, then y, then a stable window ID for exact
  overlaps. Off-screen windows and negative positions are supported.
- Only the current virtual desktop participates. All-desktops windows appear
  too. Minimized windows keep their last position. Floating windows and windows
  on other monitors participate using their global coordinates.
- The order stays fixed while cycling unless KWin rebuilds the eligible window
  list after a window is added or removed.

This follows actual window geometry. It does not read Karousel's private stack
order when windows completely overlap. Karousel needs no modification.

## Required settings

The installer selects **ScrollTab**, enables the **Current desktop** filter,
disables application grouping and the desktop entry, and sets native sorting
to **Recently used**. That native order lets ScrollTab recognize forward and
reverse steps; ScrollTab translates them into spatial order.
Window highlighting/dimming is disabled so the real windows remain visible
while Karousel scrolls. Focus previews can trigger applications' normal focus
behavior, just like clicking a window.

## Smooth scrolling with Geometry Change

The highlight glides between thumbnails in 110 ms. Focus previews are batched
in 16 ms intervals, so very fast repeats skip intermediate desktop rearrangements
while keeping every keyboard selection and the final choice intact.

For the installed **Geometry Change 1.5** extension, this project also includes
an adaptation that replaces overlapping motion animations with one continuous
translation/scale animation from the current visual position. It keeps the
configured duration and uses gentler OutCubic easing. Pure scrolling uses only
translation, without an unnecessary scale animation or forced blur. The popup
is created after its model is ready, avoiding an empty first layout.
Live thumbnails are loaded asynchronously near the visible strip, including
one neighboring cell on each side. Distant cached entries retain their icons
and captions without keeping full window snapshot sources alive.
The Geometry Change adaptation affects all windows animated by that effect,
including normal Karousel focus switching.

```sh
python3 tools/smooth_geometry.py install --activate
```

The tool verifies the supported source version and saves the original file in
the extension directory. Restore it with:

```sh
python3 tools/smooth_geometry.py restore --activate
```

Geometry Change is by Peter Fajdiga. Its adapted source in `geometry-change/`
is licensed under GPL-3.0-only; the switcher retains its GPL-2.0-or-later license.
Motion continuity tests run with `node tests/test_geometry_motion.cjs`.

The popup delay is set to **zero**. This is necessary so quick Alt+Tab taps use
ScrollTab's ordering too. Do not change the native sort mode or restore the
delay while ScrollTab is selected. The new switcher appears in **System
Settings → Window Management → Task Switcher**.

There is one backend limitation: if Alt is released before KDE dispatches its
shortcut callback, KWin bypasses the popup and uses its native MRU fallback.
ScrollTab cannot intercept that path as a local switcher package. The virtual
input checks pass with 15 ms Tab presses as well as held Alt; zero-duration
synthetic presses can take the fallback path.

The implementation targets and is checked against stock **KWin 6.6.6**. Its
model adapter uses two shared KWin model role numbers and should be checked
again after KWin upgrades.

Validation: all eight controller cases, three installer cases, and ten real
Alt+Tab scenarios passed in an isolated stock KWin 6.6.6 session.

## Restore

```sh
python3 tools/install.py uninstall --activate
```

This restores the previous user settings. It refuses to overwrite managed
settings you independently changed after installation; the original config and
installation manifest are kept in `~/.local/share/kwin/tabbox/` for review.
Package files remain available for rollback. Updates use a new package ID so
KWin loads fresh QML instead of retaining a cached older switcher.

## Tests

```sh
python3 -m unittest discover -s tests
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qmltestrunner -input tests/qml
```

`tools/smoke.py` starts an isolated virtual stock KWin session with temporary
config and data directories. It tests actual quick and held Alt+Tab input,
reverse traversal, non-wrapping edges, current-desktop filtering, sticky windows, and
Escape cancellation. Its `tools/send_keys.c` driver only permits the named
test socket. Build that driver against Wayland's client library and a generated
client header/code for Plasma's `fake-input.xml`; then run:

```sh
dbus-run-session -- python3 tools/smoke.py --input /path/to/scrolltab-test-keys
```

The virtual test relaxes protocol permission checks only inside its separate
test compositor. It does not send input to your desktop.

## Attribution

The visual layout is adapted from KDE KWin 6.6.6's
`src/tabbox/switchers/thumbnail_grid/contents/ui/main.qml`, by Chris Holland and
Nate Graham. Original notices are retained. All project code is
**GPL-2.0-or-later**; see [LICENSE](LICENSE).
