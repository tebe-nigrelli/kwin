/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick

Item {
    id: root
    required property QtObject manager
    required property Item desktopRepeater
    required property real gridValue
    required property real overviewValue

    property string hoveredDesktopId: ""
    property int hoveredPort: -1
    property var hoveredEdge: ({})

    visible: manager && manager.ready && manager.showHandles && gridValue > 0.9
    z: 1000

    function mappedRect(item) {
        if (!item) return Qt.rect(0, 0, 0, 0);
        // Explicit state dependencies make mapToItem bindings refresh while Grid View animates.
        const dependency = gridValue + overviewValue + item.deltaColumn + item.deltaRow;
        const p1 = item.mapToItem(root, 0, 0);
        const p2 = item.mapToItem(root, item.width, 0);
        const p3 = item.mapToItem(root, 0, item.height);
        const p4 = item.mapToItem(root, item.width, item.height);
        const minX = Math.min(p1.x, p2.x, p3.x, p4.x);
        const maxX = Math.max(p1.x, p2.x, p3.x, p4.x);
        const minY = Math.min(p1.y, p2.y, p3.y, p4.y);
        const maxY = Math.max(p1.y, p2.y, p3.y, p4.y);
        return Qt.rect(minX, minY, maxX - minX, maxY - minY);
    }

    function pointForRect(rect, port) {
        switch (port) {
        case 0: return Qt.point(rect.x + rect.width / 2, rect.y);
        case 1: return Qt.point(rect.x + rect.width, rect.y);
        case 2: return Qt.point(rect.x + rect.width, rect.y + rect.height / 2);
        case 3: return Qt.point(rect.x + rect.width, rect.y + rect.height);
        case 4: return Qt.point(rect.x + rect.width / 2, rect.y + rect.height);
        case 5: return Qt.point(rect.x, rect.y + rect.height);
        case 6: return Qt.point(rect.x, rect.y + rect.height / 2);
        case 7: return Qt.point(rect.x, rect.y);
        }
        return Qt.point(rect.x + rect.width / 2, rect.y + rect.height / 2);
    }

    function overlayForDesktop(id) {
        for (let i = 0; i < desktopOverlays.count; ++i) {
            const item = desktopOverlays.itemAt(i);
            if (item && item.desktopId === id) return item;
        }
        return null;
    }

    function pointForDesktopPort(id, port) {
        const item = overlayForDesktop(id);
        return item ? item.pointForPort(port) : Qt.point(0, 0);
    }

    function centerForDesktop(id) {
        const item = overlayForDesktop(id);
        return item ? item.centerPoint : Qt.point(0, 0);
    }

    onHoveredDesktopIdChanged: hoveredEdge = hoveredDesktopId !== "" && hoveredPort >= 0 ? manager.edgeInfo(hoveredDesktopId, hoveredPort) : ({})
    onHoveredPortChanged: hoveredEdge = hoveredDesktopId !== "" && hoveredPort >= 0 ? manager.edgeInfo(hoveredDesktopId, hoveredPort) : ({})

    Connections {
        target: manager
        function onRevisionChanged() {
            root.hoveredEdge = root.hoveredDesktopId !== "" && root.hoveredPort >= 0 ? root.manager.edgeInfo(root.hoveredDesktopId, root.hoveredPort) : ({});
        }
    }

    TopologyBridge {
        anchors.fill: parent
        visible: root.manager.showBridgePreview && root.hoveredEdge.exists === true && root.hoveredEdge.targetId !== undefined
        startPoint: root.pointForDesktopPort(root.hoveredDesktopId, root.hoveredPort)
        endPoint: root.centerForDesktop(root.hoveredEdge.targetId || "")
        bidirectional: root.hoveredEdge.bidirectional === true
        z: 0
    }

    Repeater {
        id: desktopOverlays
        model: root.desktopRepeater.count

        delegate: Item {
            id: desktopOverlay
            required property int index
            anchors.fill: parent

            readonly property Item sourceItem: root.desktopRepeater.itemAt(index)
            readonly property string desktopId: sourceItem && sourceItem.desktop ? sourceItem.desktop.id : ""
            readonly property string desktopName: sourceItem && sourceItem.desktop ? sourceItem.desktop.name : ""
            readonly property rect bounds: root.mappedRect(sourceItem)
            readonly property point centerPoint: Qt.point(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)

            function pointForPort(port) { return root.pointForRect(bounds, port); }

            Repeater {
                model: 8
                delegate: TopologyPort {
                    required property int index
                    readonly property point anchorPoint: desktopOverlay.pointForPort(index)
                    x: anchorPoint.x - width / 2
                    y: anchorPoint.y - height / 2
                    manager: root.manager
                    desktopId: desktopOverlay.desktopId
                    desktopName: desktopOverlay.desktopName
                    port: index
                    edge: {
                        root.manager.revision;
                        return root.manager.edgeInfo(desktopOverlay.desktopId, index);
                    }
                    selected: root.manager.selectedDesktop === desktopOverlay.desktopId && root.manager.selectedPort === index
                    z: 2
                    onHoverStateChanged: (hovering) => {
                        if (hovering) {
                            root.hoveredDesktopId = desktopOverlay.desktopId;
                            root.hoveredPort = index;
                        } else if (root.hoveredDesktopId === desktopOverlay.desktopId && root.hoveredPort === index) {
                            root.hoveredDesktopId = "";
                            root.hoveredPort = -1;
                        }
                    }
                }
            }

            TopologyTarget {
                x: centerPoint.x - width / 2
                y: centerPoint.y - height / 2
                manager: root.manager
                desktopId: desktopOverlay.desktopId
                desktopName: desktopOverlay.desktopName
                visible: root.manager.selectedDesktop !== ""
                z: 1
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.manager.cancelSelection()
    }
}
