/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

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
    property var presetModel: []
    property string presetStatus: ""
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
                                 + root.width + root.height + root.overlayEpoch);
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

    function adjacentOverlay(desktopOverlay, port) {
        if (!desktopOverlay || !desktopOverlay.sourceItem) return null;
        const row = desktopOverlay.sourceItem.row;
        const column = desktopOverlay.sourceItem.column;
        switch (port) {
        case 0: return overlayAtGrid(row - 1, column);
        case 2: return overlayAtGrid(row, column + 1);
        case 4: return overlayAtGrid(row + 1, column);
        case 6: return overlayAtGrid(row, column - 1);
        default: return null;
        }
    }

    function normalAdjacentSymbol(desktopOverlay, port) {
        if (port !== 0 && port !== 2 && port !== 4 && port !== 6) return "";
        const target = adjacentOverlay(desktopOverlay, port);
        if (!target) return "";

        root.manager.revision;
        const edge = root.manager.edgeInfo(desktopOverlay.desktopId, port);
        if (edge.exists !== true || edge.targetId !== target.desktopId) return "";

        // Each endpoint owns its own half of a bidirectional marker. This keeps
        // both port hit targets independently selectable/unlinkable.
        return port === 0 || port === 6 ? "<=" : "=>";
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

    function refreshPresets() {
        presetModel = manager ? manager.presetNames() : [];
        if (presetCombo && manager && manager.activeProfile !== "") {
            const index = presetModel.indexOf(manager.activeProfile);
            if (index >= 0) presetCombo.currentIndex = index;
        }
    }

    function loadPreset(name) {
        if (!manager || name === "") return;
        presetStatus = manager.applyPreset(name);
        refreshPresets();
    }

    function savePreset() {
        if (!manager) return;
        const name = presetName.text.trim();
        if (name === "") {
            presetStatus = "Enter a preset name";
            return;
        }
        presetStatus = manager.storePreset(name);
        if (presetStatus === "") {
            presetName.text = name;
            refreshPresets();
        }
    }

    FrameAnimation {
        running: root.visible
        onTriggered: root.overlayEpoch++
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
            root.overlayEpoch++;
            root.hoveredEdge = root.hoveredDesktopId !== "" && root.hoveredPort >= 0 ? root.manager.edgeInfo(root.hoveredDesktopId, root.hoveredPort) : ({});
        }
        function onProfilesChanged() { root.refreshPresets(); }
        function onStateChanged() { root.refreshPresets(); }
    }

    Rectangle {
        id: presetBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - 2 * Kirigami.Units.largeSpacing, presetRow.implicitWidth + 2 * Kirigami.Units.smallSpacing)
        height: presetRow.implicitHeight + 2 * Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.90)
        border.width: 1
        border.color: Kirigami.Theme.textColor
        z: 20

        Row {
            id: presetRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            PC3.ComboBox {
                id: presetCombo
                width: 170
                model: root.presetModel
                onActivated: root.loadPreset(currentText)
            }

            PC3.TextField {
                id: presetName
                width: 150
                placeholderText: "Preset name"
                onAccepted: root.savePreset()
            }

            PC3.Button {
                text: "Save"
                onClicked: root.savePreset()
            }

            PC3.Button {
                text: "Delete"
                onClicked: {
                    root.presetStatus = root.manager.removePreset(presetCombo.currentText);
                    root.refreshPresets();
                }
            }

            PC3.Label {
                width: 210
                elide: Text.ElideRight
                text: root.presetStatus === "" ? (root.manager.activeProfile === "" ? "Custom" : root.manager.activeProfile) : root.presetStatus
            }
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
            readonly property rect bounds: root.mappedRect(sourceItem && sourceItem.topologyAnchorItem ? sourceItem.topologyAnchorItem : sourceItem)
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

    Component.onCompleted: refreshPresets()

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
