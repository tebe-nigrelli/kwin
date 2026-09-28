/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    required property QtObject manager
    required property string desktopId
    required property string desktopName
    required property int port
    required property var edge
    property bool selected: false
    property string connectionSymbol: ""
    property real symbolRotation: 0
    readonly property bool hovering: mouse.containsMouse
    signal hoverStateChanged(bool hovering)
    signal pairingStarted(point scenePosition)
    signal pairingMoved(point scenePosition)
    signal pairingFinished(point scenePosition)
    signal pairingCancelled()

    width: 48
    height: 48
    Accessible.role: Accessible.Button
    Accessible.name: edge.portName + " topology port of " + desktopName

    Rectangle {
        id: dot
        anchors.centerIn: parent
        visible: root.connectionSymbol === ""
        width: 24
        height: 24
        radius: width / 2
        color: {
            if (root.edge.exists === true) {
                const alpha = root.edge.state === "custom" ? 0.72 : 0.42;
                return Qt.rgba(Kirigami.Theme.highlightColor.r,
                               Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, alpha);
            }
            // A removed/blocked edge is intentionally shown as the same empty
            // handle as an unused port. The blocked override still prevents
            // traversal; the UI does not leave a red "x" behind.
            return Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.50);
        }
        border.width: root.selected ? 3 : 2
        border.color: root.edge.exists === true ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        scale: mouse.containsMouse || root.selected ? 1.22 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.centerIn: parent
            visible: root.edge.exists === true && root.edge.bidirectional === true
            width: parent.width + 9
            height: parent.height + 9
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: parent.border.color
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.connectionSymbol !== ""
        width: 36
        height: 28
        radius: 7
        color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                       Kirigami.Theme.highlightColor.g,
                       Kirigami.Theme.highlightColor.b,
                       root.edge.exists === true ? 0.48 : 0.20)
        border.width: root.selected ? 3 : 1
        border.color: Kirigami.Theme.highlightColor
        scale: mouse.containsMouse || root.selected ? 1.12 : 1.0

        Text {
            anchors.centerIn: parent
            text: root.connectionSymbol
            rotation: root.symbolRotation
            color: Kirigami.Theme.textColor
            font.pixelSize: 16
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true

        function scenePoint(event) {
            return root.mapToItem(null, event.x, event.y);
        }

        onContainsMouseChanged: root.hoverStateChanged(containsMouse)
        onPressed: (event) => root.pairingStarted(scenePoint(event))
        onPositionChanged: (event) => {
            if (pressed) {
                root.pairingMoved(scenePoint(event));
            }
        }
        onReleased: (event) => root.pairingFinished(scenePoint(event))
        onCanceled: root.pairingCancelled()
        onDoubleClicked: (event) => {
            root.manager.unlinkPort(root.desktopId, root.port);
            root.pairingCancelled();
            event.accepted = true;
        }
    }
}
