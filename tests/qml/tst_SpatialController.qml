import QtQuick
import QtTest
import "../../switcher/contents/ui"

TestCase {
    name: "SpatialController"
    QtObject {
        id: model
        property var ids: ["middle", "farRight", "left", "lower", "sticky"]
        signal modelReset()
        function rowCount() { return ids.length; }
        function index(row, column) { return row; }
        function data(row, role) { return ids[row]; }
    }
    QtObject {
        id: native
        property var model: model
        property bool visible: false
        property bool noModifierGrab: false
        property int currentIndex: 0
    }
    SpatialController {
        id: controller
        switcher: native
        windows: [
            {internalId:"middle", frameGeometry:{x:400,y:0}},
            {internalId:"farRight", frameGeometry:{x:2600,y:0}},
            {internalId:"left", frameGeometry:{x:-2000,y:0}},
            {internalId:"lower", frameGeometry:{x:400,y:300}},
            {internalId:"sticky", frameGeometry:{x:1600,y:0}}
        ]
    }
    QtObject {
        id: liveWorkspace
        property var activeWindow: null
    }
    function init() {
        native.visible = false;
        controller.workspace = null;
        native.noModifierGrab = false;
        native.currentIndex = 0;
        model.ids = ["middle", "farRight", "left", "lower", "sticky"];
    }
    function test_live_focus_and_cancel_restore() {
        liveWorkspace.activeWindow = controller.windows[0];
        controller.workspace = liveWorkspace;
        native.currentIndex = 1;
        native.visible = true;
        tryCompare(liveWorkspace, "activeWindow", controller.windows[3]);
        native.currentIndex = 4;
        tryCompare(liveWorkspace, "activeWindow", controller.windows[4]);
        native.visible = false;
        compare(liveWorkspace.activeWindow.internalId, "middle");
    }
    function test_focus_burst_skips_intermediate_windows() {
        liveWorkspace.activeWindow = controller.windows[0];
        controller.workspace = liveWorkspace;
        native.currentIndex = 1;
        native.visible = true;
        native.currentIndex = 4;
        compare(liveWorkspace.activeWindow.internalId, "middle");
        tryCompare(liveWorkspace, "activeWindow", controller.windows[4]);
        native.visible = false;
        wait(40);
        compare(liveWorkspace.activeWindow.internalId, "middle");
    }
    function test_forward_stops_at_right_edge() {
        native.currentIndex = 1; // KWin's initial MRU step
        native.visible = true;
        compare(controller.rows.map(function(r){return r.id;}).join(","), "left,middle,lower,sticky,farRight");
        compare(controller.rows[controller.selectedRow].id, "lower");
        compare(native.currentIndex, 3);
        native.currentIndex = 4; // KWin's next native step
        compare(controller.rows[controller.selectedRow].id, "sticky");
        native.currentIndex = 0;
        compare(controller.rows[controller.selectedRow].id, "farRight");
        native.currentIndex = 2;
        compare(controller.rows[controller.selectedRow].id, "farRight");
        compare(native.currentIndex, 1);
        native.currentIndex = 2;
        compare(native.currentIndex, 1);
        native.currentIndex = 0; // reverse away from the edge
        compare(controller.rows[controller.selectedRow].id, "sticky");
    }
    function test_reverse_stops_at_left_edge() {
        native.currentIndex = model.rowCount() - 1;
        native.visible = true;
        compare(controller.rows[controller.selectedRow].id, "left");
        compare(native.currentIndex, 2);
        native.currentIndex = 1;
        compare(controller.rows[controller.selectedRow].id, "left");
        compare(native.currentIndex, 2);
        native.currentIndex = 3; // forward away from the edge
        compare(controller.rows[controller.selectedRow].id, "middle");
    }
    function test_arrow_selection_clamps() {
        native.visible = true;
        controller.select(-10);
        compare(controller.rows[controller.selectedRow].id, "left");
        controller.select(100);
        compare(controller.rows[controller.selectedRow].id, "farRight");
    }
    function test_two_windows_data() {
        return [
            { tag: "active_left", ids: ["left", "middle"] },
            { tag: "active_right", ids: ["middle", "left"] }
        ];
    }
    function test_two_windows(data) {
        model.ids = data.ids;
        native.currentIndex = 1; // Forward and reverse have the same target.
        native.visible = true;
        compare(controller.rows[controller.selectedRow].id, data.ids[1]);
        compare(native.currentIndex, 1);
        for (var i = 0; i < 4; ++i) {
            native.currentIndex = 0;
            compare(controller.rows[controller.selectedRow].id, data.ids[0]);
            native.currentIndex = 1;
            compare(controller.rows[controller.selectedRow].id, data.ids[1]);
        }
    }
    function test_two_windows_no_modifier() {
        model.ids = ["middle", "left"];
        native.noModifierGrab = true;
        native.visible = true;
        compare(controller.rows[controller.selectedRow].id, "middle");
    }
    function test_no_modifier_popup() {
        native.noModifierGrab = true;
        native.visible = true;
        compare(controller.rows[controller.selectedRow].id, "middle");
    }
    function test_removal_preserves_selected_identity() {
        native.currentIndex = 1;
        native.visible = true;
        model.ids = ["middle", "farRight", "lower", "sticky"];
        model.modelReset();
        compare(controller.rows[controller.selectedRow].id, "lower");
        compare(native.currentIndex, 2);
    }
    function test_order_frozen_during_geometry_changes() {
        native.currentIndex = 1;
        native.visible = true;
        var windows = controller.windows;
        var x = windows[0].frameGeometry.x;
        windows[0].frameGeometry.x = -5000;
        compare(controller.rows[0].id, "left");
        windows[0].frameGeometry.x = x;
    }
}
