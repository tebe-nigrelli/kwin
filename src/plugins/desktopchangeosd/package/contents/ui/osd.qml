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
            showGraph = KWin.readConfig("TextOnly", "false") !== "true";
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

                const w = width;
                const h = height;
                const margin = 34;
                const cx = w / 2;
                const cy = h / 2;
                const radius = Math.max(20, Math.min(w, h) * 0.34);
                let p = [];

                if (n === 1) {
                    p.push({ x: cx, y: cy });
                } else {
                    for (let i = 0; i < n; ++i) {
                        const angle = -Math.PI / 2 + i * 2 * Math.PI / Math.max(1, n);
                        p.push({ x: cx + Math.cos(angle) * radius,
                                 y: cy + Math.sin(angle) * radius });
                    }
                }

                const restLength = Math.max(72, Math.min(125, Math.min(w, h) * 0.38));
                for (let iteration = 0; iteration < 100 && n > 1; ++iteration) {
                    let fx = new Array(n).fill(0);
                    let fy = new Array(n).fill(0);

                    for (let i = 0; i < n; ++i) {
                        for (let j = i + 1; j < n; ++j) {
                            let dx = p[i].x - p[j].x;
                            let dy = p[i].y - p[j].y;
                            let d2 = dx * dx + dy * dy;
                            if (d2 < 16) {
                                dx += (i + 1) * 0.37;
                                dy += (j + 1) * 0.29;
                                d2 = dx * dx + dy * dy;
                            }
                            const d = Math.sqrt(d2);
                            const repel = 5200 / d2;
                            const ux = dx / d;
                            const uy = dy / d;
                            fx[i] += ux * repel;
                            fy[i] += uy * repel;
                            fx[j] -= ux * repel;
                            fy[j] -= uy * repel;
                        }
                    }

                    for (let e = 0; e < edges.length; ++e) {
                        const edge = edges[e];
                        const dx = p[edge.b].x - p[edge.a].x;
                        const dy = p[edge.b].y - p[edge.a].y;
                        const d = Math.max(1, Math.sqrt(dx * dx + dy * dy));
                        const spring = (d - restLength) * 0.018;
                        const ux = dx / d;
                        const uy = dy / d;
                        fx[edge.a] += ux * spring;
                        fy[edge.a] += uy * spring;
                        fx[edge.b] -= ux * spring;
                        fy[edge.b] -= uy * spring;
                    }

                    for (let i = 0; i < n; ++i) {
                        fx[i] += (cx - p[i].x) * 0.003;
                        fy[i] += (cy - p[i].y) * 0.003;
                        p[i].x = Math.max(margin, Math.min(w - margin, p[i].x + fx[i] * 0.72));
                        p[i].y = Math.max(margin, Math.min(h - margin, p[i].y + fy[i] * 0.72));
                    }
                }

                positions = p;
                graphEdges = edges;
                layoutEpoch++;
                edgeCanvas.requestPaint();
            }

            function nodePosition(index) {
                layoutEpoch;
                if (index < 0 || index >= positions.length) return Qt.point(width / 2, height / 2);
                return Qt.point(positions[index].x, positions[index].y);
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
                        const a = topologyGraph.nodePosition(edge.a);
                        const b = topologyGraph.nodePosition(edge.b);
                        ctx.beginPath();
                        ctx.moveTo(a.x, a.y);
                        ctx.lineTo(b.x, b.y);
                        ctx.stroke();
                        if (edge.aToB) topologyGraph.drawArrow(ctx, a, b, 19);
                        if (edge.bToA) topologyGraph.drawArrow(ctx, b, a, 19);
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
        topologyGraph.rebuildGraph();
        textElement.text = current.name;
        dialog.visible = true;
        dialog.x = screenGeometry.x + screenGeometry.width / 2 - dialogItem.width / 2;
        dialog.y = screenGeometry.y + screenGeometry.height / 2 - dialogItem.height / 2;
        timer.restart();
    }
}
