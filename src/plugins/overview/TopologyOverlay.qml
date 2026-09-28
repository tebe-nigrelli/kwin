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

    property point pairingPosition: Qt.point(-10000, -10000)
    property string targetDesktopId: ""
    property bool targetAccepting: false
    property bool targetBidirectional: false
    property int overlayEpoch: 0
    readonly property bool pairing: manager && manager.selectedDesktop !== "" && manager.selectedPort >= 0
    readonly property real targetOuterRadius: 68
    readonly property real targetInnerRadius: 40

    visible: manager && manager.ready && manager.showHandles && gridValue > 0.9
    z: 1000

    function mappedRect(item) {
        if (!item) return Qt.rect(0, 0, 0, 0);
        // mapToItem() itself does not expose every transform dependency to the
        // binding engine. Reading them here keeps the handles glued to the
        // desktop while Grid View animates or resizes.
        const dependencyX = 0 * (gridValue + overviewValue + item.x + item.y
                                 + item.width + item.height + item.deltaColumn + item.deltaRow
                                 + root.width + root.height);
        const p1 = item.mapToItem(root, dependencyX, 0);
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
        const inset = Math.max(14, Math.min(24, Math.min(rect.width, rect.height) * 0.06));
        switch (port) {
        case 0: return Qt.point(rect.x + rect.width / 2, rect.y + inset);
        case 1: return Qt.point(rect.x + rect.width - inset, rect.y + inset);
        case 2: return Qt.point(rect.x + rect.width - inset, rect.y + rect.height / 2);
        case 3: return Qt.point(rect.x + rect.width - inset, rect.y + rect.height - inset);
        case 4: return Qt.point(rect.x + rect.width / 2, rect.y + rect.height - inset);
        case 5: return Qt.point(rect.x + inset, rect.y + rect.height - inset);
        case 6: return Qt.point(rect.x + inset, rect.y + rect.height / 2);
        case 7: return Qt.point(rect.x + inset, rect.y + inset);
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

    function overlayAtGrid(row, column) {
        for (let i = 0; i < desktopOverlays.count; ++i) {
            const item = desktopOverlays.itemAt(i);
            if (!item || !item.sourceItem) continue;
            if (item.sourceItem.row === row && item.sourceItem.column === column) return item;
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

    function clearTarget() {
        targetDesktopId = "";
        targetAccepting = false;
        targetBidirectional = false;
    }

    function updateDropTarget(scenePoint) {
        pairingPosition = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        clearTarget();

        for (let i = 0; i < desktopOverlays.count; ++i) {
            const item = desktopOverlays.itemAt(i);
            if (!item || item.desktopId === "" || item.desktopId === manager.selectedDesktop) continue;
            const rect = item.bounds;
            if (pairingPosition.x < rect.x || pairingPosition.x > rect.x + rect.width
                    || pairingPosition.y < rect.y || pairingPosition.y > rect.y + rect.height) {
                continue;
            }

            targetDesktopId = item.desktopId;
            const dx = pairingPosition.x - item.centerPoint.x;
            const dy = pairingPosition.y - item.centerPoint.y;
            const distance = Math.sqrt(dx * dx + dy * dy);
            targetAccepting = distance <= targetOuterRadius;
            targetBidirectional = distance <= targetInnerRadius;
            return;
        }
    }

    function beginPairing(desktopId, port, scenePoint) {
        manager.selectPort(desktopId, port);
        updateDropTarget(scenePoint);
    }

    function movePairing(scenePoint) {
        if (pairing) updateDropTarget(scenePoint);
    }

    function finishPairing(scenePoint) {
        if (!pairing) return;
        updateDropTarget(scenePoint);
        if (targetAccepting && targetDesktopId !== "") {
            manager.linkSelectedTo(targetDesktopId, targetBidirectional);
        } else {
            manager.cancelSelection();
        }
        clearTarget();
    }

    function cancelPairing() {
        if (pairing) manager.cancelSelection();
        clearTarget();
    }

    function normalAdjacentSymbol(desktopOverlay, port) {
        if (!desktopOverlay || !desktopOverlay.sourceItem) return "";
        // Render one label per shared edge, on the east or south side only.
        if (port !== 2 && port !== 4) return "";

        const row = desktopOverlay.sourceItem.row;
        const column = desktopOverlay.sourceItem.column;
        const target = port === 2 ? overlayAtGrid(row, column + 1) : overlayAtGrid(row + 1, column);
        if (!target) return "";

        root.manager.revision;
        const forward = root.manager.edgeInfo(desktopOverlay.desktopId, port);
        const reversePort = (port + 4) % 8;
        const reverse = root.manager.edgeInfo(target.desktopId, reversePort);
        const forwardConnected = forward.exists === true && forward.targetId === target.desktopId;
        const reverseConnected = reverse.exists === true && reverse.targetId === desktopOverlay.desktopId;
        if (forwardConnected && reverseConnected) return "<=>";
        if (forwardConnected) return "=>";
        if (reverseConnected) return "<=";
        return "";
    }

    function torusSplitSymbol(desktopOverlay, port) {
        if (!desktopOverlay || !desktopOverlay.sourceItem || root.manager.activeProfile !== "Torus") return "";
        root.manager.revision;
        const edge = root.manager.edgeInfo(desktopOverlay.desktopId, port);
        if (edge.exists !== true || edge.effectiveBidirectional !== true || edge.targetId === undefined) return "";
        const target = overlayForDesktop(edge.targetId || "");
        if (!target || !target.sourceItem) return "";

        const sourceRow = desktopOverlay.sourceItem.row;
        const sourceColumn = desktopOverlay.sourceItem.column;
        const targetRow = target.sourceItem.row;
        const targetColumn = target.sourceItem.column;
        if (port === 2 && targetColumn < sourceColumn && targetRow === sourceRow) return "=>";
        if (port === 6 && targetColumn > sourceColumn && targetRow === sourceRow) return "<=";
        if (port === 4 && targetRow < sourceRow && targetColumn === sourceColumn) return "=>";
        if (port === 0 && targetRow > sourceRow && targetColumn === sourceColumn) return "<=";
        return "";
    }

    function connectionSymbol(desktopOverlay, port) {
        root.overlayEpoch;
        const split = torusSplitSymbol(desktopOverlay, port);
        return split !== "" ? split : normalAdjacentSymbol(desktopOverlay, port);
    }

    function symbolRotation(port) {
        return port === 0 || port === 4 ? 90 : 0;
    }

    onHoveredDesktopIdChanged: hoveredEdge = hoveredDesktopId !== "" && hoveredPort >= 0 ? manager.edgeInfo(hoveredDesktopId, hoveredPort) : ({})
    onHoveredPortChanged: hoveredEdge = hoveredDesktopId !== "" && hoveredPort >= 0 ? manager.edgeInfo(hoveredDesktopId, hoveredPort) : ({})
    onGridValueChanged: {
        if (pairing && gridValue < 0.9) cancelPairing();
    }
    onVisibleChanged: {
        if (!visible && pairing) cancelPairing();
    }

    Connections {
        target: manager
        function onRevisionChanged() {
            root.hoveredEdge = root.hoveredDesktopId !== "" && root.hoveredPort >= 0 ? root.manager.edgeInfo(root.hoveredDesktopId, root.hoveredPort) : ({});
        }
    }

    TopologyBridge {
        anchors.fill: parent
        visible: root.pairing
        startPoint: root.pointForDesktopPort(root.manager.selectedDesktop, root.manager.selectedPort)
        endPoint: root.targetAccepting ? root.centerForDesktop(root.targetDesktopId) : root.pairingPosition
        bidirectional: root.targetAccepting && root.targetBidirectional
        z: 0
    }

    TopologyBridge {
        anchors.fill: parent
        visible: !root.pairing && root.manager.showBridgePreview && root.hoveredEdge.exists === true && root.hoveredEdge.targetId !== undefined
        startPoint: root.pointForDesktopPort(root.hoveredDesktopId, root.hoveredPort)
        endPoint: root.centerForDesktop(root.hoveredEdge.targetId || "")
        bidirectional: root.hoveredEdge.bidirectional === true
        z: 0
    }

    Repeater {
        id: desktopOverlays
        model: root.desktopRepeater.count
        onItemAdded: root.overlayEpoch++
        onItemRemoved: root.overlayEpoch++

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
                    connectionSymbol: root.connectionSymbol(desktopOverlay, index)
                    symbolRotation: root.symbolRotation(index)
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
                    onPairingStarted: (scenePosition) => root.beginPairing(desktopOverlay.desktopId, index, scenePosition)
                    onPairingMoved: (scenePosition) => root.movePairing(scenePosition)
                    onPairingFinished: (scenePosition) => root.finishPairing(scenePosition)
                    onPairingCancelled: root.cancelPairing()
                }
            }

            TopologyTarget {
                x: centerPoint.x - width / 2
                y: centerPoint.y - height / 2
                manager: root.manager
                desktopId: desktopOverlay.desktopId
                desktopName: desktopOverlay.desktopName
                accepting: root.targetAccepting
                bidirectional: root.targetBidirectional
                visible: root.pairing && root.targetDesktopId === desktopOverlay.desktopId
                z: 1
            }
        }
    }

    Shortcut {
        sequence: "Esc"
        enabled: root.pairing
        onActivated: root.cancelPairing()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.cancelPairing()
    }
}
