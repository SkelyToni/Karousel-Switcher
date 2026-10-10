// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import "Order.js" as Order

QtObject {
    id: controller
    property var switcher
    property var windows: []
    property var windowProvider: null
    property var workspace: null
    property var originalWindow: null
    property var rows: []
    property int selectedRow: -1
    property int lastNative: -1
    property bool adjusting: false
    property bool initialized: false
    signal previewFocused()
    // Thumbnail captures by window id, kept across openings.
    property var snapshots: ({})
    // True once Karousel's motion from the last focus change has finished.
    // Thumbnail rendering and captures wait for it.
    property bool settled: true
    property Timer settleTimer: Timer {
        interval: 300
        onTriggered: controller.settled = true
    }
    // Focus on the next event-loop pass, outside KWin's tabbox signal
    // handlers. Selections made in the same pass (opening plus KWin's first
    // step) collapse into one Karousel rearrangement. Key repeats arrive
    // ~30 ms apart, so a longer delay would only postpone each motion.
    property int focusDelay: 0
    property Timer focusFrame: Timer {
        interval: controller.focusDelay
        onTriggered: controller.focusSelected()
    }

    function select(row) {
        row = rows.length ? Math.max(0, Math.min(row, rows.length - 1)) : -1;
        var changed = row !== selectedRow;
        selectedRow = row;
        if (row < 0) return;
        adjusting = true;
        lastNative = rows[row].nativeIndex;
        switcher.currentIndex = lastNative;
        adjusting = false;
        if ((changed || !initialized) && !focusFrame.running) focusFrame.start();
    }

    // Step through the row, wrapping from the last window to the first and back.
    function move(delta) {
        select(Order.wrap(selectedRow + delta, rows.length));
    }

    function focusSelected() {
        if (!switcher.visible || selectedRow < 0) return;
        // Real focus lets Karousel scroll the selected column into view.
        if (workspace) {
            // Use the window captured with the row; searching KWin's full
            // window list on every step is avoidable work during motion.
            var target = rows[selectedRow].window;
            if (!target) {
                var candidates = windowProvider ? windowProvider() : windows;
                var id = rows[selectedRow].id;
                target = candidates.find(function(window) { return String(window.internalId) === id; });
            }
            if (target && workspace.activeWindow !== target) {
                settled = false;
                settleTimer.restart();
                workspace.activeWindow = target;
            }
        }
        previewFocused();
    }

    // KWin closes the popup, then activates the accepted window; Escape only
    // closes it. The switcher cannot see which: KWin keeps the abort flag
    // internal, and activating the already-focused preview is silent.
    // Clearing focus makes acceptance observable without moving any window:
    // Karousel ignores an empty focus, and the accepted window is already in
    // view. If nothing claimed focus by the next pass, the popup was
    // cancelled, so restore the starting window.
    property var previewWindow: null
    property Timer restoreCheck: Timer {
        interval: 0
        onTriggered: controller.finishClose()
    }

    function closeFocus() {
        if (!workspace || !originalWindow) {
            originalWindow = null;
            return;
        }
        previewWindow = workspace.activeWindow;
        if (previewWindow === originalWindow) {
            originalWindow = previewWindow = null;
            return;
        }
        workspace.activeWindow = null;
        restoreCheck.start();
    }

    function finishClose() {
        restoreCheck.stop();
        if (workspace && workspace.activeWindow === null) {
            var candidates = windowProvider ? windowProvider() : windows;
            var target = candidates.indexOf(originalWindow) >= 0 ? originalWindow :
                candidates.indexOf(previewWindow) >= 0 ? previewWindow : null;
            if (target) workspace.activeWindow = target;
        }
        originalWindow = previewWindow = null;
    }

    // Keep the view's delegates and loaded thumbnails when the visible list
    // is unchanged (a new opening, or a model reset that changes nothing
    // visible); only KWin's native row numbers move.
    function adopt(snapshot) {
        if (Order.sameEntries(rows, snapshot)) {
            for (var i = 0; i < rows.length; ++i) {
                rows[i].nativeIndex = snapshot[i].nativeIndex;
                rows[i].window = snapshot[i].window;
            }
        } else {
            rows = snapshot;
        }
    }

    function begin() {
        if (restoreCheck.running) finishClose();
        initialized = false;
        originalWindow = workspace ? workspace.activeWindow : null;
        var firstNative = switcher.currentIndex;
        // Opening starts Karousel's first motion; hold thumbnail work until
        // it settles, even if no focus change follows.
        settled = false;
        settleTimer.restart();
        var all = windowProvider ? windowProvider() : windows;
        adopt(Order.snapshot(switcher.model, all));
        // Drop captures of windows that no longer exist.
        var kept = {};
        all.forEach(function(window) {
            var id = String(window.internalId);
            if (snapshots[id]) kept[id] = snapshots[id];
        });
        snapshots = kept;
        // MRU puts the active window at native row 0. KWin has already made
        // the first forward/reverse step before it shows the popup.
        var origin = Order.rowForNative(rows, 0);
        var step = switcher.noModifierGrab || firstNative === 0 ? 0 :
            firstNative === rows.length - 1 && rows.length > 2 ? -1 : 1;
        // With two entries, forward and reverse both select native row 1.
        // Their direction cannot be recovered from the index; honor KWin's
        // target instead of guessing a spatial step.
        if (rows.length === 2) select(Order.rowForNative(rows, firstNative));
        else select(Order.wrap(origin + step, rows.length));
        initialized = true;
    }

    function nativeChanged() {
        if (adjusting || !initialized || !switcher.visible) return;
        var next = switcher.currentIndex;
        if (next === lastNative) return;
        if (rows.length === 2) {
            select(Order.rowForNative(rows, next));
            return;
        }
        var step = Order.direction(lastNative, next, rows.length);
        if (step) move(step);
        else select(Order.rowForNative(rows, next));
    }

    function rebuild() {
        if (!initialized || !switcher.visible) return;
        var selectedId = selectedRow >= 0 ? rows[selectedRow].id : "";
        var previousRow = selectedRow;
        adjusting = true;
        var snapshot = Order.snapshot(switcher.model, windowProvider ? windowProvider() : windows);
        adopt(snapshot);
        var next = rows.findIndex(function(row) { return row.id === selectedId; });
        adjusting = false;
        select(next < 0 ? Math.min(previousRow, rows.length - 1) : next);
    }

    function activate(row) {
        if (row >= 0 && row < rows.length)
            switcher.model.activate(rows[row].nativeIndex);
    }

    function closeWindow(row) {
        if (row >= 0 && row < rows.length && typeof switcher.model.close === "function")
            switcher.model.close(rows[row].nativeIndex);
    }

    property Connections switcherConnection: Connections {
        target: controller.switcher
        function onVisibleChanged() {
            if (controller.switcher.visible) controller.begin();
            else {
                controller.focusFrame.stop();
                controller.initialized = false;
                controller.closeFocus();
            }
        }
        function onCurrentIndexChanged() { controller.nativeChanged(); }
    }
    property Connections modelConnection: Connections {
        target: controller.switcher ? controller.switcher.model : null
        function onModelReset() { controller.rebuild(); }
    }
}
