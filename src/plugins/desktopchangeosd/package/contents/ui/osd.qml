/*
    KWin - the KDE window manager
    SPDX-FileCopyrightText: 2012, 2013 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kwin

PlasmaCore.Window {
    id: dialog
    visible: false
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint

    width: mainItem.implicitWidth + leftPadding + rightPadding
    height: mainItem.implicitHeight + topPadding + bottomPadding

    mainItem: Item {
        id: dialogItem

        property int screenWidth: 0
        property int screenHeight: 0
        property int currentIndex: 0
        property int previousIndex: 0
        property int animationDuration: 1000
        property bool showGraph: true

        function loadConfig() {
            animationDuration = KWin.readConfig("PopupHideDelay", 1000);
            // Topos uses the graph as the desktop-layout indicator. Keep it
            // visible whenever the topology manager is available, even if an
            // older TextOnly setting was left behind in kwinrc.
            showGraph = Workspace.topos && Workspace.topos.ready
                ? true
                : KWin.readConfig("TextOnly", "false") !== "true";
        }

        implicitWidth: showGraph ? topologyGraph.width : Math.ceil(textElement.implicitWidth)
        implicitHeight: showGraph ? textElement.implicitHeight + topologyGraph.height : textElement.implicitHeight

        Kirigami.Heading {
            id: textElement
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        Item {
            id: topologyGraph
            anchors.top: textElement.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(280, Math.min(520, dialogItem.screenWidth * 0.38))
            height: Math.max(190, Math.min(340, dialogItem.screenHeight * 0.28))
            visible: dialogItem.showGraph

            property var positions: []
            property var graphEdges: []
            property int layoutEpoch: 0

            function desktopIndexById(id) {
                const desktops = Workspace.desktops;
                for (let i = 0; i < desktops.length; ++i) {
                    if (desktops[i].id === id) return i;
                }
                return -1;
            }

            function graphGridPositions(w, h, n) {
                const margin = 34;
                const rows = Math.max(1, Workspace.desktopGridHeight);
                const columns = Math.max(1, Math.ceil(n / rows));
                const rowSpan = Math.max(1, rows - 1);
                const columnSpan = Math.max(1, columns - 1);
                const usableW = Math.max(1, w - 2 * margin);
                const usableH = Math.max(1, h - 2 * margin);
                const result = [];
                for (let i = 0; i < n; ++i) {
                    const row = Math.floor(i / columns);
                    const column = i % columns;
                    result.push({
                        x: columns === 1 ? w / 2 : margin + column / columnSpan * usableW,
                        y: rows === 1 ? h / 2 : margin + row / rowSpan * usableH
                    });
                }
                return result;
            }

            function graphLoosePositions(w, h, n, edges) {
                const margin = 30;
                const cx = w / 2;
                const cy = h / 2;
                const spread = Workspace.topos ? Workspace.topos.topologyGraphSpread : 1.35;
                let p = graphGridPositions(w, h, n);
                if (n > 1) {
                    for (let i = 0; i < n; ++i) {
                        const angle = i * 2.399963229728653;
                        p[i].x += Math.cos(angle) * 5;
                        p[i].y += Math.sin(angle) * 5;
                    }
                }

                const restLength = Math.max(54, Math.min(150, Math.min(w, h) * 0.30 * spread));
                const repulsion = 5600 * spread * spread;
                for (let iteration = 0; iteration < 130 && n > 1; ++iteration) {
                    let fx = new Array(n).fill(0);
                    let fy = new Array(n).fill(0);
                    for (let i = 0; i < n; ++i) {
                        for (let j = i + 1; j < n; ++j) {
                            let dx = p[i].x - p[j].x;
                            let dy = p[i].y - p[j].y;
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
                        const dx = p[edge.b].x - p[edge.a].x;
                        const dy = p[edge.b].y - p[edge.a].y;
                        const d = Math.max(1, Math.sqrt(dx * dx + dy * dy));
                        const spring = (d - restLength) * 0.018;
                        fx[edge.a] += dx / d * spring;
                        fy[edge.a] += dy / d * spring;
                        fx[edge.b] -= dx / d * spring;
                        fy[edge.b] -= dy / d * spring;
                    }
                    for (let i = 0; i < n; ++i) {
                        fx[i] += (cx - p[i].x) * 0.0035;
                        fy[i] += (cy - p[i].y) * 0.0035;
                        p[i].x = Math.max(margin, Math.min(w - margin, p[i].x + fx[i] * 0.78));
                        p[i].y = Math.max(margin, Math.min(h - margin, p[i].y + fy[i] * 0.78));
                    }
                }
                return p;
            }

            function rebuildGraph() {
                const desktops = Workspace.desktops;
                const n = desktops.length;
                const edgesByPair = {};
                const edges = [];
                const manager = Workspace.topos;

                if (manager && manager.ready) {
                    for (let source = 0; source < n; ++source) {
                        for (let port = 0; port < 8; ++port) {
                            const info = manager.edgeInfo(desktops[source].id, port);
                            if (info.exists !== true || info.targetId === undefined) continue;
                            const target = desktopIndexById(info.targetId);
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
                }

                const loose = manager && manager.topologyGraphLayout === "loose";
                positions = loose
                    ? graphLoosePositions(width, height, n, edges)
                    : graphGridPositions(width, height, n);
                graphEdges = edges;
                layoutEpoch++;
                edgeCanvas.requestPaint();
            }

            function nodePosition(index) {
                layoutEpoch;
                if (index < 0 || index >= positions.length) return Qt.point(width / 2, height / 2);
                return Qt.point(positions[index].x, positions[index].y);
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

            function routePenalty(points, edge) {
                let penalty = 0;
                let length = 0;
                for (let segment = 0; segment + 1 < points.length; ++segment) {
                    const a = points[segment];
                    const b = points[segment + 1];
                    const dx = b.x - a.x;
                    const dy = b.y - a.y;
                    length += Math.sqrt(dx * dx + dy * dy);
                    for (let i = 0; i < positions.length; ++i) {
                        if (i === edge.a || i === edge.b) continue;
                        const node = nodePosition(i);
                        const d2 = segmentDistanceSquared(node, a, b);
                        if (d2 < 24 * 24) penalty += 100000 + (24 * 24 - d2) * 100;
                        else if (d2 < 38 * 38) penalty += (38 * 38 - d2) * 4;
                    }
                }
                return penalty + length;
            }

            function graphRoute(edge) {
                const a = nodePosition(edge.a);
                const b = nodePosition(edge.b);
                if (Workspace.topos && Workspace.topos.topologyGraphLayout === "loose") {
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
                    if (a.y + lane < height - 18) candidates.push([a, Qt.point(a.x, a.y + lane), Qt.point(b.x, b.y + lane), b]);
                } else if (Math.abs(dx) < 2) {
                    const lane = 26 + ((edge.a + edge.b) % 3) * 7;
                    if (a.x - lane > 18) candidates.push([a, Qt.point(a.x - lane, a.y), Qt.point(b.x - lane, b.y), b]);
                    if (a.x + lane < width - 18) candidates.push([a, Qt.point(a.x + lane, a.y), Qt.point(b.x + lane, b.y), b]);
                } else {
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
                let bestPenalty = routePenalty(best, edge);
                for (let i = 1; i < candidates.length; ++i) {
                    const penalty = routePenalty(candidates[i], edge);
                    if (penalty < bestPenalty) {
                        bestPenalty = penalty;
                        best = candidates[i];
                    }
                }
                return best;
            }

            function drawArrow(ctx, from, to, nodeRadius) {
                const dx = to.x - from.x;
                const dy = to.y - from.y;
                const d = Math.sqrt(dx * dx + dy * dy);
                if (d < 1) return;
                const ux = dx / d;
                const uy = dy / d;
                const tipX = to.x - ux * nodeRadius;
                const tipY = to.y - uy * nodeRadius;
                const size = 8;
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

            Canvas {
                id: edgeCanvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.lineWidth = 2;
                    ctx.strokeStyle = Kirigami.Theme.textColor;
                    ctx.globalAlpha = 0.68;

                    for (let i = 0; i < topologyGraph.graphEdges.length; ++i) {
                        const edge = topologyGraph.graphEdges[i];
                        const route = topologyGraph.graphRoute(edge);
                        if (route.length < 2) continue;
                        ctx.beginPath();
                        ctx.moveTo(route[0].x, route[0].y);
                        for (let j = 1; j < route.length; ++j) {
                            ctx.lineTo(route[j].x, route[j].y);
                        }
                        ctx.stroke();
                        if (edge.aToB) topologyGraph.drawArrow(ctx, route[route.length - 2], route[route.length - 1], 19);
                        if (edge.bToA) topologyGraph.drawArrow(ctx, route[1], route[0], 19);
                    }
                }
            }

            Repeater {
                model: Workspace.desktops

                Rectangle {
                    required property int index
                    readonly property QtObject desktop: Workspace.desktops[index]
                    readonly property point graphPosition: topologyGraph.nodePosition(index)
                    x: graphPosition.x - width / 2
                    y: graphPosition.y - height / 2
                    width: index === dialogItem.currentIndex ? 42 : 34
                    height: width
                    radius: width / 2
                    color: index === dialogItem.currentIndex ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
                    border.width: index === dialogItem.currentIndex ? 3 : 2
                    border.color: Kirigami.Theme.textColor

                    Text {
                        anchors.centerIn: parent
                        text: parent.index + 1
                        color: parent.index === dialogItem.currentIndex ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        font.bold: parent.index === dialogItem.currentIndex
                    }

                    Text {
                        anchors.top: parent.bottom
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 100
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: parent.desktop ? parent.desktop.name : ""
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 10
                    }
                }
            }

            onWidthChanged: rebuildGraph()
            onHeightChanged: rebuildGraph()
            Component.onCompleted: rebuildGraph()

            Connections {
                target: Workspace.topos
                function onRevisionChanged() { topologyGraph.rebuildGraph(); }
                function onReadyChanged() { topologyGraph.rebuildGraph(); }
                function onDesktopSignatureChanged() { topologyGraph.rebuildGraph(); }
                function onSettingsChanged() { topologyGraph.rebuildGraph(); }
            }

            Connections {
                target: Workspace
                function onDesktopsChanged() { topologyGraph.rebuildGraph(); }
            }
        }

        Timer {
            id: timer
            repeat: false
            interval: dialogItem.animationDuration
            onTriggered: dialog.visible = false
        }

        Connections {
            target: Options
            function onConfigChanged() { dialogItem.loadConfig(); }
        }

        Component.onCompleted: dialogItem.loadConfig()
    }

    function show(previous, current, screen) {
        if (Workspace.isEffectActive("overview") || (dialog.visible && screen != Workspace.activeScreen)) {
            return;
        }
        dialogItem.previousIndex = Workspace.desktops.indexOf(previous);
        dialogItem.currentIndex = Workspace.desktops.indexOf(current);
        const screenGeometry = Workspace.clientArea(KWin.FullScreenArea, screen, current);
        dialogItem.screenWidth = screenGeometry.width;
        dialogItem.screenHeight = screenGeometry.height;
        // The graph only changes when desktops, topology, layout mode, spread,
        // or its viewport size change; those paths already rebuild it. Rebuilding
        // here made every desktop switch rerun the loose-layout solver and repaint
        // all routes on the QML GUI thread, producing a visible hitch exactly when
        // this transition preview appeared. Only the selected node changes here.
        textElement.text = current.name;
        dialog.visible = true;
        dialog.x = screenGeometry.x + screenGeometry.width / 2 - dialogItem.width / 2;
        dialog.y = screenGeometry.y + screenGeometry.height / 2 - dialogItem.height / 2;
        timer.restart();
    }
}
