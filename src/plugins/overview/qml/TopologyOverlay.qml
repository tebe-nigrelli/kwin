/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import QtQuick.Controls as QQC2
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
    property var graphPositions: []
    property var graphEdges: []
    property int graphEpoch: 0
    readonly property bool pairing: manager && manager.selectedDesktop !== "" && manager.selectedPort >= 0
    readonly property real targetOuterRadius: 68
    readonly property real targetInnerRadius: 40

    visible: manager && manager.ready && manager.showHandles && gridValue > 0.9
    z: 1000

    function mappedRect(item) {
        if (!item) return Qt.rect(0, 0, 0, 0);
        // mapToItem() itself does not expose every transform dependency to the
        // binding engine. overlayEpoch is advanced every rendered frame while
        // Grid View is visible, which keeps the handles glued to animated cards.
        // Do not read deltaColumn/deltaRow from topologyAnchorItem: the anchor is
        // backgroundArea and those properties live on its parent. Reading the
        // missing properties produced NaN geometry and made most ports disappear.
        root.overlayEpoch;
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

    // Connected adjacent ports sit directly against the desktop boundary.
    // Each endpoint owns only its own half of the marker, so the two hit areas
    // do not overlap and either direction can still be selected independently.
    function pointForConnectedRect(rect, port) {
        const inset = 15;
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
        if (!item) return Qt.point(0, 0);
        return connectionSymbol(item, port) !== ""
            ? pointForConnectedRect(item.bounds, port)
            : item.pointForPort(port);
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
        const dr = [-1, -1, 0, 1, 1, 1, 0, -1];
        const dc = [0, 1, 1, 1, 0, -1, -1, -1];
        return overlayAtGrid(row + dr[port], column + dc[port]);
    }

    function splitSymbolForPort(port) {
        switch (port) {
        case 0: return "<=";
        case 1: return "=>";
        case 2: return "=>";
        case 3: return "=>";
        case 4: return "=>";
        case 5: return "<=";
        case 6: return "<=";
        case 7: return "<=";
        }
        return "";
    }

    function connectionSymbol(desktopOverlay, port) {
        // Render the directional half on every connected endpoint, not only
        // when the target happens to occupy the neighbouring grid cell. This
        // keeps custom and wrapped links visible on both ends.
        root.overlayEpoch;
        root.manager.revision;
        const edge = root.manager.edgeInfo(desktopOverlay.desktopId, port);
        return edge.exists === true ? splitSymbolForPort(port) : "";
    }

    function symbolRotation(port) {
        switch (port) {
        case 0: return 90;
        case 1: return -45;
        case 2: return 0;
        case 3: return 45;
        case 4: return 90;
        case 5: return -45;
        case 6: return 0;
        case 7: return 45;
        }
        return 0;
    }

    function graphDesktopId(index) {
        const item = root.desktopRepeater.itemAt(index);
        return item && item.desktop ? item.desktop.id : "";
    }

    function graphDesktopName(index) {
        const item = root.desktopRepeater.itemAt(index);
        return item && item.desktop ? item.desktop.name : (index + 1).toString();
    }

    function graphDesktopIndex(id) {
        for (let i = 0; i < root.desktopRepeater.count; ++i) {
            if (graphDesktopId(i) === id) return i;
        }
        return -1;
    }

    function graphGridPositions(w, h, n) {
        const margin = 28;
        let minRow = 100000;
        let maxRow = -100000;
        let minColumn = 100000;
        let maxColumn = -100000;
        const grid = [];
        for (let i = 0; i < n; ++i) {
            const item = root.desktopRepeater.itemAt(i);
            const row = item && item.row !== undefined ? item.row : Math.floor(i / Math.max(1, Math.ceil(Math.sqrt(n))));
            const column = item && item.column !== undefined ? item.column : i % Math.max(1, Math.ceil(Math.sqrt(n)));
            grid.push({ row: row, column: column });
            minRow = Math.min(minRow, row);
            maxRow = Math.max(maxRow, row);
            minColumn = Math.min(minColumn, column);
            maxColumn = Math.max(maxColumn, column);
        }
        const rowSpan = Math.max(1, maxRow - minRow);
        const columnSpan = Math.max(1, maxColumn - minColumn);
        const usableW = Math.max(1, w - 2 * margin);
        const usableH = Math.max(1, h - 2 * margin);
        const positions = [];
        for (let i = 0; i < n; ++i) {
            const x = maxColumn === minColumn
                ? w / 2
                : margin + (grid[i].column - minColumn) / columnSpan * usableW;
            const y = maxRow === minRow
                ? h / 2
                : margin + (grid[i].row - minRow) / rowSpan * usableH;
            positions.push({ x: x, y: y });
        }
        return positions;
    }

    function graphLoosePositions(w, h, n, edges) {
        const margin = 30;
        const cx = w / 2;
        const cy = h / 2;
        const spread = root.manager ? root.manager.topologyGraphSpread : 1.35;
        let positions = graphGridPositions(w, h, n);
        if (n > 1) {
            // Add a deterministic nudge so symmetric grids can actually loosen.
            for (let i = 0; i < n; ++i) {
                const angle = i * 2.399963229728653;
                positions[i].x += Math.cos(angle) * 5;
                positions[i].y += Math.sin(angle) * 5;
            }
        }

        const restLength = Math.max(54, Math.min(150, Math.min(w, h) * 0.30 * spread));
        const repulsion = 5600 * spread * spread;
        for (let iteration = 0; iteration < 130 && n > 1; ++iteration) {
            let fx = new Array(n).fill(0);
            let fy = new Array(n).fill(0);
            for (let i = 0; i < n; ++i) {
                for (let j = i + 1; j < n; ++j) {
                    let dx = positions[i].x - positions[j].x;
                    let dy = positions[i].y - positions[j].y;
                    let d2 = dx * dx + dy * dy;
                    if (d2 < 25) d2 = 25;
                    const d = Math.sqrt(d2);
                    const repel = repulsion / d2;
                    fx[i] += dx / d * repel;
                    fy[i] += dy / d * repel;
                    fx[j] -= dx / d * repel;
                    fy[j] -= dy / d * repel;
                }
            }
            for (let e = 0; e < edges.length; ++e) {
                const edge = edges[e];
                const dx = positions[edge.b].x - positions[edge.a].x;
                const dy = positions[edge.b].y - positions[edge.a].y;
                const d = Math.max(1, Math.sqrt(dx * dx + dy * dy));
                const spring = (d - restLength) * 0.018;
                fx[edge.a] += dx / d * spring;
                fy[edge.a] += dy / d * spring;
                fx[edge.b] -= dx / d * spring;
                fy[edge.b] -= dy / d * spring;
            }
            for (let i = 0; i < n; ++i) {
                fx[i] += (cx - positions[i].x) * 0.0035;
                fy[i] += (cy - positions[i].y) * 0.0035;
                positions[i].x = Math.max(margin, Math.min(w - margin, positions[i].x + fx[i] * 0.78));
                positions[i].y = Math.max(margin, Math.min(h - margin, positions[i].y + fy[i] * 0.78));
            }
        }
        return positions;
    }

    function rebuildGraph() {
        if (!graphPanel) return;
        const n = root.desktopRepeater.count;
        const edgesByPair = {};
        const edges = [];

        for (let source = 0; source < n; ++source) {
            const sourceId = graphDesktopId(source);
            if (sourceId === "") continue;
            for (let port = 0; port < 8; ++port) {
                const info = root.manager.edgeInfo(sourceId, port);
                if (info.exists !== true || info.targetId === undefined) continue;
                const target = graphDesktopIndex(info.targetId);
                if (target < 0 || target === source) continue;
                const a = Math.min(source, target);
                const b = Math.max(source, target);
                const key = a + ":" + b;
                let edge = edgesByPair[key];
                if (edge === undefined) {
                    edge = { a: a, b: b, aToB: false, bToA: false };
                    edgesByPair[key] = edge;
                    edges.push(edge);
                }
                if (source === a) edge.aToB = true;
                else edge.bToA = true;
            }
        }

        const w = graphArea ? graphArea.width : graphPanel.width;
        const h = graphArea ? graphArea.height : graphPanel.height;
        const loose = root.manager && root.manager.topologyGraphLayout === "loose";
        root.graphPositions = loose
            ? graphLoosePositions(w, h, n, edges)
            : graphGridPositions(w, h, n);
        root.graphEdges = edges;
        root.graphEpoch++;
        graphCanvas.requestPaint();
    }

    function graphPosition(index) {
        root.graphEpoch;
        if (index < 0 || index >= root.graphPositions.length) return Qt.point(graphArea.width / 2, graphArea.height / 2);
        return Qt.point(root.graphPositions[index].x, root.graphPositions[index].y);
    }

    function segmentDistanceSquared(point, a, b) {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const length2 = dx * dx + dy * dy;
        if (length2 < 0.001) {
            const px = point.x - a.x;
            const py = point.y - a.y;
            return px * px + py * py;
        }
        const t = Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length2));
        const qx = a.x + t * dx;
        const qy = a.y + t * dy;
        const px = point.x - qx;
        const py = point.y - qy;
        return px * px + py * py;
    }

    function graphRoutePenalty(points, edge) {
        let penalty = 0;
        let length = 0;
        for (let segment = 0; segment + 1 < points.length; ++segment) {
            const a = points[segment];
            const b = points[segment + 1];
            const dx = b.x - a.x;
            const dy = b.y - a.y;
            length += Math.sqrt(dx * dx + dy * dy);
            for (let i = 0; i < root.graphPositions.length; ++i) {
                if (i === edge.a || i === edge.b) continue;
                const node = graphPosition(i);
                const d2 = segmentDistanceSquared(node, a, b);
                if (d2 < 24 * 24) {
                    penalty += 100000 + (24 * 24 - d2) * 100;
                } else if (d2 < 38 * 38) {
                    penalty += (38 * 38 - d2) * 4;
                }
            }
        }
        return penalty + length;
    }

    function graphRoute(edge) {
        const a = graphPosition(edge.a);
        const b = graphPosition(edge.b);
        if (root.manager && root.manager.topologyGraphLayout === "loose") {
            return [a, b];
        }

        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const sx = dx >= 0 ? 1 : -1;
        const sy = dy >= 0 ? 1 : -1;
        const xStep = Math.max(18, Math.min(Math.abs(dx) * 0.34, 34));
        const yStep = Math.max(18, Math.min(Math.abs(dy) * 0.34, 34));
        const candidates = [[a, b]];

        if (Math.abs(dy) < 2) {
            const lane = 26 + ((edge.a + edge.b) % 3) * 7;
            if (a.y - lane > 18) candidates.push([a, Qt.point(a.x, a.y - lane), Qt.point(b.x, b.y - lane), b]);
            if (a.y + lane < graphArea.height - 18) candidates.push([a, Qt.point(a.x, a.y + lane), Qt.point(b.x, b.y + lane), b]);
        } else if (Math.abs(dx) < 2) {
            const lane = 26 + ((edge.a + edge.b) % 3) * 7;
            if (a.x - lane > 18) candidates.push([a, Qt.point(a.x - lane, a.y), Qt.point(b.x - lane, b.y), b]);
            if (a.x + lane < graphArea.width - 18) candidates.push([a, Qt.point(a.x + lane, a.y), Qt.point(b.x + lane, b.y), b]);
        } else {
            // Orthogonal dog-leg candidates. They use corridors between grid
            // nodes; route scoring below picks the one that clears the most
            // node centres. Each candidate itself is non-self-intersecting.
            candidates.push([a, Qt.point(a.x, a.y + sy * yStep),
                             Qt.point(b.x - sx * xStep, a.y + sy * yStep),
                             Qt.point(b.x - sx * xStep, b.y), b]);
            candidates.push([a, Qt.point(a.x + sx * xStep, a.y),
                             Qt.point(a.x + sx * xStep, b.y - sy * yStep),
                             Qt.point(b.x, b.y - sy * yStep), b]);
            candidates.push([a, Qt.point(b.x, a.y), b]);
            candidates.push([a, Qt.point(a.x, b.y), b]);
        }

        let best = candidates[0];
        let bestPenalty = graphRoutePenalty(best, edge);
        for (let i = 1; i < candidates.length; ++i) {
            const penalty = graphRoutePenalty(candidates[i], edge);
            if (penalty < bestPenalty) {
                bestPenalty = penalty;
                best = candidates[i];
            }
        }
        return best;
    }

    function drawGraphArrow(ctx, from, to, nodeRadius) {
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1) return;
        const ux = dx / d;
        const uy = dy / d;
        const tipX = to.x - ux * nodeRadius;
        const tipY = to.y - uy * nodeRadius;
        const size = 7;
        const backX = tipX - ux * size;
        const backY = tipY - uy * size;
        const px = -uy;
        const py = ux;
        ctx.beginPath();
        ctx.moveTo(tipX, tipY);
        ctx.lineTo(backX + px * size * 0.55, backY + py * size * 0.55);
        ctx.moveTo(tipX, tipY);
        ctx.lineTo(backX - px * size * 0.55, backY - py * size * 0.55);
        ctx.stroke();
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
            root.rebuildGraph();
        }
        function onProfilesChanged() { root.refreshPresets(); root.rebuildGraph(); }
        function onStateChanged() { root.refreshPresets(); root.rebuildGraph(); }
        function onSettingsChanged() { root.rebuildGraph(); }
    }

    Rectangle {
        id: graphPanel
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        width: Math.min(360, Math.max(260, parent.width * 0.25))
        height: Math.min(220, Math.max(180, parent.height * 0.22))
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
        border.width: 1
        border.color: Kirigami.Theme.textColor
        z: 18

        Column {
            id: graphControls
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 3

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    text: "Topology"
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                PC3.ComboBox {
                    id: graphLayoutCombo
                    width: 112
                    model: ["Grid", "Loose DAG"]
                    currentIndex: root.manager && root.manager.topologyGraphLayout === "loose" ? 1 : 0
                    onActivated: {
                        root.manager.topologyGraphLayout = currentIndex === 1 ? "loose" : "grid";
                        Qt.callLater(root.rebuildGraph);
                    }
                    PC3.ToolTip.text: "Graph layout. Grid is the default; Loose DAG uses force-directed placement."
                    PC3.ToolTip.visible: hovered
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                opacity: root.manager && root.manager.topologyGraphLayout === "loose" ? 1.0 : 0.45

                PC3.Label {
                    text: "Spread"
                    anchors.verticalCenter: parent.verticalCenter
                }

                QQC2.Slider {
                    id: graphSpreadSlider
                    width: 145
                    from: 0.75
                    to: 2.5
                    stepSize: 0.05
                    enabled: root.manager && root.manager.topologyGraphLayout === "loose"
                    value: root.manager ? root.manager.topologyGraphSpread : 1.35
                    onMoved: {
                        root.manager.topologyGraphSpread = value;
                        root.rebuildGraph();
                    }
                }

                PC3.Label {
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    text: (root.manager ? root.manager.topologyGraphSpread : 1.35).toFixed(1) + "x"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item {
            id: graphArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: graphControls.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.bottomMargin: 4
            anchors.topMargin: 2

            Canvas {
                id: graphCanvas
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.lineWidth = 2;
                    ctx.strokeStyle = Kirigami.Theme.textColor;
                    ctx.globalAlpha = 0.76;
                    for (let i = 0; i < root.graphEdges.length; ++i) {
                        const edge = root.graphEdges[i];
                        const route = root.graphRoute(edge);
                        if (route.length < 2) continue;
                        ctx.beginPath();
                        ctx.moveTo(route[0].x, route[0].y);
                        for (let j = 1; j < route.length; ++j) {
                            ctx.lineTo(route[j].x, route[j].y);
                        }
                        ctx.stroke();
                        if (edge.aToB) root.drawGraphArrow(ctx, route[route.length - 2], route[route.length - 1], 15);
                        if (edge.bToA) root.drawGraphArrow(ctx, route[1], route[0], 15);
                    }
                }
            }

            onWidthChanged: Qt.callLater(root.rebuildGraph)
            onHeightChanged: Qt.callLater(root.rebuildGraph)

            Repeater {
                model: root.desktopRepeater.count
                Rectangle {
                    required property int index
                    readonly property point panelPosition: root.graphPosition(index)
                    x: panelPosition.x - width / 2
                    y: panelPosition.y - height / 2
                    width: 30
                    height: 30
                    radius: 15
                    readonly property Item sourceDesktopItem: root.desktopRepeater.itemAt(index)
                    color: sourceDesktopItem && sourceDesktopItem.current
                        ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
                    border.width: 2
                    border.color: Kirigami.Theme.textColor

                    PC3.Label {
                        anchors.centerIn: parent
                        text: parent.index + 1
                        font.bold: true
                    }
                }
            }
        }

        onWidthChanged: Qt.callLater(root.rebuildGraph)
        onHeightChanged: Qt.callLater(root.rebuildGraph)
        Component.onCompleted: Qt.callLater(root.rebuildGraph)
    }

    // Keep the preset toolbar away from the top-edge/corner topology handles.
    // It now lives below the graph panel instead of spanning the top desktop row.
    Rectangle {
        id: presetBar
        anchors.top: graphPanel.bottom
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - 2 * Kirigami.Units.largeSpacing, presetRow.implicitWidth + 2 * Kirigami.Units.smallSpacing)
        height: presetRow.implicitHeight + 2 * Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
        border.width: 1
        border.color: Kirigami.Theme.textColor
        z: 20

        Row {
            id: presetRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            PC3.ComboBox {
                id: presetCombo
                width: 140
                model: root.presetModel
                onActivated: root.loadPreset(currentText)
            }

            PC3.TextField {
                id: presetName
                width: 130
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
                width: 150
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
        onItemAdded: { root.overlayEpoch++; Qt.callLater(root.rebuildGraph); }
        onItemRemoved: { root.overlayEpoch++; Qt.callLater(root.rebuildGraph); }

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
                    readonly property point anchorPoint: connectionSymbol !== ""
                        ? root.pointForConnectedRect(desktopOverlay.bounds, index)
                        : desktopOverlay.pointForPort(index)
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

    Component.onCompleted: { refreshPresets(); Qt.callLater(rebuildGraph); }

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
