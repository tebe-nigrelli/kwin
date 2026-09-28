/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: root
    required property QtObject manager
    required property string desktopId
    required property string desktopName
    property bool accepting: false
    property bool bidirectional: false

    width: 136
    height: 136
    Accessible.role: Accessible.Button
    Accessible.name: "Topology target " + desktopName

    Rectangle {
        id: oneWayTarget
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(Kirigami.Theme.neutralTextColor.r,
                       Kirigami.Theme.neutralTextColor.g,
                       Kirigami.Theme.neutralTextColor.b,
                       root.accepting && !root.bidirectional ? 0.72 : 0.42)
        border.width: root.accepting && !root.bidirectional ? 5 : 3
        border.color: Kirigami.Theme.neutralTextColor

        HoverHandler { id: oneWayHover }
        PC3.ToolTip.text: "One-way link: release here to connect to " + root.desktopName
        PC3.ToolTip.visible: oneWayHover.hovered && !twoWayHover.hovered
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            text: "→"
            color: Kirigami.Theme.textColor
            font.pixelSize: 18
            font.bold: true
        }
    }

    Rectangle {
        id: twoWayTarget
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: width / 2
        color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                       Kirigami.Theme.highlightColor.g,
                       Kirigami.Theme.highlightColor.b,
                       root.accepting && root.bidirectional ? 0.92 : 0.68)
        border.width: root.accepting && root.bidirectional ? 5 : 3
        border.color: Kirigami.Theme.highlightColor

        HoverHandler { id: twoWayHover }
        PC3.ToolTip.text: "Two-way link: release here to connect both directions with " + root.desktopName
        PC3.ToolTip.visible: twoWayHover.hovered
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay

        Text {
            anchors.centerIn: parent
            text: "↔"
            color: Kirigami.Theme.textColor
            font.pixelSize: 20
            font.bold: true
        }
    }
}
