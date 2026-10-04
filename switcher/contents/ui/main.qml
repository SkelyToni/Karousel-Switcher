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

    Instantiator {
        // Build the dialog only once its model and selection are ready.
        active: tabBox.visible && spatial.initialized
        delegate: PlasmaCore.Dialog {
            id: popup
            // Native highlighting normally elevates the tabbox. Live focus
            // needs that effect disabled, so elevate the popup independently.
            type: PlasmaCore.Dialog.OnScreenDisplay
            hideOnWindowDeactivate: false
            location: PlasmaCore.Types.Floating
            visible: true
            // Qt.Popup auto-dismisses when live focus moves to an application.
            // KWin already owns the Alt+Tab input grab, so use a tool overlay.
            flags: Qt.Tool | Qt.X11BypassWindowManagerHint | Qt.WindowStaysOnTopHint
            property Timer popupRepair: Timer {
                interval: 0
                onTriggered: {
                    if (tabBox.visible && !popup.visible) popup.show();
                }
            }
            property Connections previewConnection: Connections {
                target: spatial
                function onPreviewFocused() {
                    // KWin/Qt may hide internal windows during an activation.
                    // Re-show after that focus transition has completed.
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
                    cacheBuffer: cellWidth * 2

                    readonly property int iconSize: Kirigami.Units.iconSizes.huge
                    readonly property int captionRowHeight: Kirigami.Units.gridUnit * 2
                    readonly property int columnSpacing: Kirigami.Units.gridUnit
                    readonly property int thumbnailWidth: Kirigami.Units.gridUnit * 16
                    readonly property int thumbnailHeight: thumbnailWidth * (1.0/dialogMainItem.screenFactor)
                    readonly property real cellWidth: hoverItem.margins.left + thumbnailWidth + hoverItem.margins.right
                    readonly property real cellHeight: hoverItem.margins.top + captionRowHeight + thumbnailHeight + hoverItem.margins.bottom

                    keyNavigationWraps: false
                    keyNavigationEnabled: false
                    highlightMoveDuration: 110
                    highlightMoveVelocity: -1

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

                                Loader {
                                    objectName: "scrolltabThumbnailLoader"
                                    anchors.fill: parent
                                    // Keep one neighbor ready on each side;
                                    // cached distant delegates need no full-size
                                    // compositor snapshot until they approach.
                                    active: thumbnailGridItem.x + thumbnailGridItem.width >=
                                        thumbnailGridView.contentX - thumbnailGridView.cellWidth &&
                                        thumbnailGridItem.x <= thumbnailGridView.contentX +
                                        thumbnailGridView.width + thumbnailGridView.cellWidth
                                    asynchronous: true
                                    sourceComponent: KWin.WindowThumbnail {
                                        wId: modelData.windowId
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
                    if (step) spatial.select(spatial.selectedRow + step);
                    event.accepted = true;
                }
            } // Dialog.mainItem

            onSceneGraphError: () => {
                // This slot is intentionally left blank, otherwise QtQuick may post a qFatal() message on a graphics reset.
            }
        } // Dialog
    } // Instantiator
}
