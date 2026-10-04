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
    // Coalesce key-repeat bursts instead of asking Karousel to rearrange its
    // entire desktop for intermediate selections that never reach a frame.
    property Timer focusFrame: Timer {
        interval: 16
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

    function focusSelected() {
        if (!switcher.visible || selectedRow < 0) return;
        // Real focus lets Karousel scroll the selected column into view.
        if (workspace) {
            var candidates = windowProvider ? windowProvider() : windows;
            var id = rows[selectedRow].id;
            var target = candidates.find(function(window) { return String(window.internalId) === id; });
            if (target && workspace.activeWindow !== target) workspace.activeWindow = target;
        }
        previewFocused();
    }

    function begin() {
        initialized = false;
        originalWindow = workspace ? workspace.activeWindow : null;
        var firstNative = switcher.currentIndex;
        rows = Order.snapshot(switcher.model, windowProvider ? windowProvider() : windows);
        // MRU puts the active window at native row 0. KWin has already made
        // the first forward/reverse step before it shows the popup.
        var origin = Order.rowForNative(rows, 0);
        var step = switcher.noModifierGrab || firstNative === 0 ? 0 :
            firstNative === rows.length - 1 && rows.length > 2 ? -1 : 1;
        // With two entries, forward and reverse both select native row 1.
        // Their direction cannot be recovered from the index; honor KWin's
        // target instead of clamping a guessed spatial step at an edge.
        select(rows.length === 2 ? Order.rowForNative(rows, firstNative) : origin + step);
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
        select(step ? selectedRow + step : Order.rowForNative(rows, next));
    }

    function rebuild() {
        if (!initialized || !switcher.visible) return;
        var selectedId = selectedRow >= 0 ? rows[selectedRow].id : "";
        var previousRow = selectedRow;
        adjusting = true;
        rows = Order.snapshot(switcher.model, windowProvider ? windowProvider() : windows);
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
                // KWin closes the popup before committing its selected window.
                // Restore first: Escape leaves this focus intact; acceptance
                // immediately activates the final selection again.
                if (controller.workspace && controller.originalWindow) {
                    var candidates = controller.windowProvider ? controller.windowProvider() : controller.windows;
                    if (candidates.indexOf(controller.originalWindow) >= 0)
                        controller.workspace.activeWindow = controller.originalWindow;
                }
                controller.originalWindow = null;
            }
        }
        function onCurrentIndexChanged() { controller.nativeChanged(); }
    }
    property Connections modelConnection: Connections {
        target: controller.switcher ? controller.switcher.model : null
        function onModelReset() { controller.rebuild(); }
    }
}
