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
    readonly property bool hovering: hover.hovered
    signal hoverStateChanged(bool hovering)

    width: 32
    height: 32
    Accessible.role: Accessible.Button
    Accessible.name: edge.portName + " topology port of " + desktopName

    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: 14
        height: 14
        radius: 7
        color: root.edge.state === "custom" ? Kirigami.Theme.highlightColor : "transparent"
        border.width: root.selected || root.edge.state === "custom" ? 2 : 1
        border.color: root.edge.state === "blocked" ? Kirigami.Theme.negativeTextColor :
                      (root.edge.state === "custom" ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor)
        scale: hover.hovered ? 1.4 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            visible: root.edge.state === "blocked"
            text: "×"
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: 12
            font.bold: true
        }

        Rectangle {
            anchors.centerIn: parent
            visible: root.edge.bidirectional === true
            width: parent.width + 6
            height: parent.height + 6
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: parent.border.color
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: root.hoverStateChanged(hovered)
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.manager.selectPort(root.desktopId, root.port)
    }
}
