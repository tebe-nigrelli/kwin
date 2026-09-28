/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    required property QtObject manager
    required property string desktopId
    required property string desktopName

    width: 112
    height: 112
    Accessible.role: Accessible.Button
    Accessible.name: "Topology target " + desktopName

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.75)
    }

    Rectangle {
        anchors.centerIn: parent
        width: 64
        height: 64
        radius: 32
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: (eventPoint) => {
            const dx = eventPoint.position.x - root.width / 2;
            const dy = eventPoint.position.y - root.height / 2;
            const bidirectional = Math.sqrt(dx * dx + dy * dy) <= 32;
            root.manager.linkSelectedTo(root.desktopId, bidirectional);
        }
    }
}
