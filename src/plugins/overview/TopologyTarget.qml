/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami

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
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(Kirigami.Theme.positiveTextColor.r,
                       Kirigami.Theme.positiveTextColor.g,
                       Kirigami.Theme.positiveTextColor.b,
                       root.accepting && !root.bidirectional ? 0.48 : 0.28)
        border.width: root.accepting ? 4 : 3
        border.color: Kirigami.Theme.positiveTextColor
    }

    Rectangle {
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: width / 2
        color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                       Kirigami.Theme.highlightColor.g,
                       Kirigami.Theme.highlightColor.b,
                       root.accepting && root.bidirectional ? 0.72 : 0.42)
        border.width: root.accepting && root.bidirectional ? 4 : 3
        border.color: Kirigami.Theme.highlightColor
    }
}
