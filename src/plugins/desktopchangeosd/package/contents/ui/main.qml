/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-FileCopyrightText: 2012 Martin Gräßlin <mgraesslin@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.kwin

Loader {
    id: mainItemLoader

    // Instantiate the OSD when the script loads instead of on the first desktop
    // change. The topology graph can then build its cached layout outside the
    // latency-sensitive desktop transition path.
    source: "osd.qml"

    Connections {
        target: Workspace
        function onCurrentDesktopChanged(previous, current, screen) {
            if (mainItemLoader.item) {
                mainItemLoader.item.show(previous, current, screen);
            }
        }
    }
}
