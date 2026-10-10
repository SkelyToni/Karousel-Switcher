/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2020 Chris Holland <zrenfire@gmail.com>
 SPDX-FileCopyrightText: 2023 Nate Graham <nate@kde.org>

 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

KWin.TabBoxSwitcher {
    id: tabBox

    SpatialController {
        id: spatial
        switcher: tabBox
        workspace: typeof KWin.Workspace !== "undefined" ? KWin.Workspace : null
        windowProvider: function() {
            // Settings' sample model does not have live KWin windows.
            return typeof KWin.Workspace !== "undefined" ? KWin.Workspace.windows : [];
        }
    }

    // Created once instead of per opening, so Alt+Tab does not build the
    // popup and a delegate per window on KWin's main thread just as
    // Karousel's first motion starts.
    PlasmaCore.Dialog {
        id: popup
        // Native highlighting normally elevates the tabbox. Live focus
        // needs that effect disabled, so elevate the popup independently.
        type: PlasmaCore.Dialog.OnScreenDisplay
        hideOnWindowDeactivate: false
        // Windows keep moving behind the popup while Karousel scrolls; a
        // translucent background would make KWin re-blur them every frame.
        backgroundHints: PlasmaCore.Dialog.SolidBackground
        location: PlasmaCore.Types.Floating
        // Show once the model and selection are ready, avoiding an empty
        // first layout. KWin destroys the native window on hide; this object,
        // its delegates and their snapshots persist across openings.
        visible: false
        readonly property bool wanted: tabBox.visible && spatial.initialized
        onWantedChanged: sync()
        function sync() {
            if (wanted && !visible) show();
            else if (!wanted && visible) hide();
        }
        // Qt.Popup auto-dismisses when live focus moves to an application,
        // and Qt.Tool windows are hidden on many focus changes, so each
        // step tore down and re-created the popup. KWin already owns the
        // Alt+Tab input grab, so use a plain frameless overlay.
        flags: Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint | Qt.WindowStaysOnTopHint
        property Timer popupRepair: Timer {
            interval: 0
            onTriggered: {
                popup.sync();
            }
        }
        property Connections previewConnection: Connections {
            target: spatial
            function onPreviewFocused() {
                // Safety net in case KWin/Qt still hides the popup during an
                // activation: re-show after the focus transition completes.
                popup.popupRepair.restart();
            }
        }
        x: tabBox.screenGeometry.x + tabBox.screenGeometry.width * 0.5 - dialogMainItem.width * 0.5
        y: tabBox.screenGeometry.y + tabBox.screenGeometry.height * 0.5 - dialogMainItem.height * 0.5

        mainItem: FocusScope {
            id: dialogMainItem

            focus: true

            property int maxWidth: tabBox.screenGeometry.width * 0.9
            property int maxHeight: tabBox.screenGeometry.height * 0.7
            property real screenFactor: tabBox.screenGeometry.width / tabBox.screenGeometry.height
            property int optimalWidth: thumbnailGridView.cellWidth * thumbnailGridView.count
            property int optimalHeight: thumbnailGridView.cellHeight
            width: Math.min(Math.max(thumbnailGridView.cellWidth, optimalWidth), maxWidth)
            height: Math.min(Math.max(thumbnailGridView.cellHeight, optimalHeight), maxHeight)

            clip: true

            // Just to get the margin sizes
            KSvg.FrameSvgItem {
                id: hoverItem
                imagePath: "widgets/viewitem"
                prefix: "hover"
                visible: false
            }

            ListView {
                id: thumbnailGridView
                anchors.fill: parent
                focus: true
                model: spatial.rows
                currentIndex: spatial.selectedRow
                orientation: ListView.Horizontal
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                preferredHighlightBegin: Math.max(0, (width - cellWidth) / 2)
                preferredHighlightEnd: preferredHighlightBegin + cellWidth
                highlightRangeMode: ListView.ApplyRange
                // Keep every delegate while the popup is open, so captured
                // snapshots survive scrolling instead of reloading live.
                cacheBuffer: Math.ceil(cellWidth * count)

                readonly property int iconSize: Kirigami.Units.iconSizes.huge
                readonly property int captionRowHeight: Kirigami.Units.gridUnit * 2
                readonly property int columnSpacing: Kirigami.Units.gridUnit
                readonly property int thumbnailWidth: Kirigami.Units.gridUnit * 16
                readonly property int thumbnailHeight: thumbnailWidth * (1.0/dialogMainItem.screenFactor)
                readonly property real cellWidth: hoverItem.margins.left + thumbnailWidth + hoverItem.margins.right
                readonly property real cellHeight: hoverItem.margins.top + captionRowHeight + thumbnailHeight + hoverItem.margins.bottom

                keyNavigationWraps: false
                keyNavigationEnabled: false
                // Move the selection frame and strip instantly. An animated
                // popup redraws every frame on KWin's main thread, competing
                // with Karousel's window motion; this redraws once per step.
                highlightFollowsCurrentItem: false

                delegate: MouseArea {
                    id: thumbnailGridItem
                    width: thumbnailGridView.cellWidth
                    height: thumbnailGridView.cellHeight
                    focus: ListView.isCurrentItem
                    hoverEnabled: true

                    Accessible.name: modelData.caption
                    Accessible.role: Accessible.ListItem

                    onClicked: {
                        spatial.activate(index);
                    }

                    ColumnLayout {
                        id: columnLayout
                        z: 0
                        spacing: thumbnailGridView.columnSpacing
                        anchors.fill: parent
                        anchors.leftMargin: hoverItem.margins.left * 2
                        anchors.topMargin: hoverItem.margins.top * 2
                        anchors.rightMargin: hoverItem.margins.right * 2
                        anchors.bottomMargin: hoverItem.margins.bottom * 2


                        // KWin.WindowThumbnail needs a container
                        // otherwise it will be drawn the same size as the parent ColumnLayout
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // A still copy of the live thumbnail. Karousel moves
                            // every window on each step, and KWin re-renders each
                            // live thumbnail at full window size when it moves.
                            // Copies persist across openings, so later popups
                            // show them without loading live thumbnails at all.
                            Image {
                                id: thumbnailSnapshot
                                objectName: "scrolltabThumbnailSnapshot"
                                anchors.fill: parent
                                cache: false
                                visible: status === Image.Ready
                                Component.onCompleted: {
                                    var cached = spatial.snapshots[modelData.id];
                                    if (cached) source = cached.url;
                                }
                            }

                            Loader {
                                id: thumbnailLoader
                                objectName: "scrolltabThumbnailLoader"
                                anchors.fill: parent
                                readonly property bool selected: thumbnailGridItem.ListView.isCurrentItem
                                readonly property bool hasSnapshot: thumbnailSnapshot.status === Image.Ready
                                property bool capturing: false
                                // Set while settled on this window; once it loses
                                // the selection, its snapshot is re-captured.
                                property bool refreshPending: false
                                // While windows move, only entries without any
                                // snapshot (or mid-capture) are live. Once motion
                                // settles, the selected window goes live to show its
                                // focused colors and current contents. Live rendering
                                // and refresh captures never compete with motion.
                                // Nothing is live while the popup is hidden: the
                                // delegates persist, and a live thumbnail keeps KWin
                                // rendering its window offscreen.
                                readonly property bool shown: popup.visible
                                onShownChanged: if (!shown) capturing = false
                                active: shown && (!hasSnapshot || capturing ||
                                    (spatial.settled && (selected || refreshPending)))
                                onActiveChanged: if (active && selected && hasSnapshot) refreshPending = true
                                asynchronous: true
                                opacity: status === Loader.Ready ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 100
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                // A first capture happens even during motion, so the
                                // cache fills on the first opening; refreshing an
                                // existing snapshot waits until motion settles.
                                readonly property bool wantsCapture: shown && status === Loader.Ready && !selected &&
                                    (!hasSnapshot || (spatial.settled && refreshPending))
                                onWantsCaptureChanged: wantsCapture ? snapshotDelay.restart() : snapshotDelay.stop()
                                sourceComponent: KWin.WindowThumbnail {
                                    wId: modelData.windowId
                                }
                                // Give KWin a few frames to render the window
                                // texture, its focus change and the fade before capturing.
                                Timer {
                                    id: snapshotDelay
                                    interval: 150
                                    onTriggered: {
                                        var thumbnail = thumbnailLoader.item;
                                        if (!thumbnailLoader.wantsCapture || !thumbnail ||
                                            thumbnail.width <= 0 || thumbnail.height <= 0) return;
                                        // Keep the live thumbnail if capture fails.
                                        var scale = Screen.devicePixelRatio || 1;
                                        var id = modelData.id;
                                        thumbnailLoader.capturing = thumbnail.grabToImage(function(result) {
                                            if (result && result.url) {
                                                spatial.snapshots[id] = result;
                                                thumbnailSnapshot.source = result.url;
                                                thumbnailLoader.refreshPending = false;
                                            }
                                            thumbnailLoader.capturing = false;
                                        }, Qt.size(Math.ceil(thumbnail.width * scale),
                                                   Math.ceil(thumbnail.height * scale)));
                                    }
                                }
                            }

                            Kirigami.Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.bottom
                                anchors.verticalCenterOffset: Math.round(-thumbnailGridView.iconSize / 4)
                                width: thumbnailGridView.iconSize
                                height: thumbnailGridView.iconSize

                                source: modelData.icon
                            }

                            PlasmaComponents3.Button {
                                id: closeButton
                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    // Deliberately touch the inner edges of the frame
                                    rightMargin: -columnLayout.anchors.rightMargin
                                    topMargin: -columnLayout.anchors.topMargin
                                }
                                visible: modelData.closeable && typeof tabBox.model.close !== 'undefined' &&
                                        (thumbnailGridItem.containsMouse
                                        || closeButton.hovered
                                        || thumbnailGridItem.focus
                                        || Kirigami.Settings.tabletMode
                                        || Kirigami.Settings.hasTransientTouchInput
                                        )
                                icon.name: 'window-close-symbolic'
                                onClicked: {
                                    spatial.closeWindow(index);
                                }
                            }
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData.caption
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                    }
                } // ListView.delegate

                highlight: KSvg.FrameSvgItem {
                    x: thumbnailGridView.currentItem ? thumbnailGridView.currentItem.x : 0
                    y: 0
                    width: thumbnailGridView.cellWidth
                    height: thumbnailGridView.cellHeight
                    imagePath: "widgets/viewitem"
                    prefix: "hover"
                }

                // SpatialController maps the visual row to KWin's selected window.
            } // ListView

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 2
                icon.source: "edit-none"
                text: i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
                visible: thumbnailGridView.count === 0
            }

            Keys.onPressed: function(event) {
                var step = 0;
                if (event.key === Qt.Key_Left) step = -1;
                else if (event.key === Qt.Key_Right) step = 1;
                else if (event.key === Qt.Key_Up) step = -1;
                else if (event.key === Qt.Key_Down) step = 1;
                else if (event.key === Qt.Key_Home) spatial.select(0);
                else if (event.key === Qt.Key_End) spatial.select(spatial.rows.length - 1);
                else return;
                if (step) spatial.move(step);
                event.accepted = true;
            }
        } // Dialog.mainItem

        onSceneGraphError: () => {
            // This slot is intentionally left blank, otherwise QtQuick may post a qFatal() message on a graphics reset.
        }
    } // Dialog
}
