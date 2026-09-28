/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: root
    property point startPoint
    property point endPoint
    property bool bidirectional: false
    anchors.fill: parent

    readonly property point controlPoint: {
        const dx = endPoint.x - startPoint.x;
        const dy = endPoint.y - startPoint.y;
        const len = Math.max(1, Math.sqrt(dx * dx + dy * dy));
        const curvature = Math.min(80, 0.18 * len);
        return Qt.point((startPoint.x + endPoint.x) / 2 - dy / len * curvature,
                        (startPoint.y + endPoint.y) / 2 + dx / len * curvature);
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 6
            strokeColor: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
            fillColor: "transparent"
            startX: root.startPoint.x
            startY: root.startPoint.y
            PathQuad { x: root.endPoint.x; y: root.endPoint.y; controlX: root.controlPoint.x; controlY: root.controlPoint.y }
        }
        ShapePath {
            strokeWidth: 2
            strokeColor: Kirigami.Theme.highlightColor
            fillColor: "transparent"
            startX: root.startPoint.x
            startY: root.startPoint.y
            PathQuad { x: root.endPoint.x; y: root.endPoint.y; controlX: root.controlPoint.x; controlY: root.controlPoint.y }
        }
    }
}
