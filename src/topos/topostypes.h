/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QHash>
#include <QPointF>
#include <QString>
#include <QtMath>

#include <cstdint>
#include <cmath>
#include <optional>

namespace KWin
{

inline constexpr int ToposApiVersion = 1;

enum class ToposPort : uint8_t {
    North = 0,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
};

struct ToposTransport
{
    int rotationSteps = 0;
    bool mirrored = false;

    bool operator==(const ToposTransport &) const = default;
};

struct ToposArc
{
    QString targetDesktopId;
    ToposTransport transport;

    bool operator==(const ToposArc &) const = default;
};

struct ToposEndpoint
{
    QString desktopId;
    ToposPort port = ToposPort::North;

    bool operator==(const ToposEndpoint &) const = default;
};

inline size_t qHash(const ToposEndpoint &endpoint, size_t seed = 0)
{
    return qHashMulti(seed, endpoint.desktopId, static_cast<int>(endpoint.port));
}

using ToposOverrideMap = QHash<ToposEndpoint, std::optional<ToposArc>>;

inline QPointF portVector(ToposPort port)
{
    constexpr qreal diagonal = 0.70710678118654752440;
    switch (port) {
    case ToposPort::North:
        return QPointF(0, -1);
    case ToposPort::NorthEast:
        return QPointF(diagonal, -diagonal);
    case ToposPort::East:
        return QPointF(1, 0);
    case ToposPort::SouthEast:
        return QPointF(diagonal, diagonal);
    case ToposPort::South:
        return QPointF(0, 1);
    case ToposPort::SouthWest:
        return QPointF(-diagonal, diagonal);
    case ToposPort::West:
        return QPointF(-1, 0);
    case ToposPort::NorthWest:
        return QPointF(-diagonal, -diagonal);
    }
    Q_UNREACHABLE();
}

inline ToposPort oppositePort(ToposPort port)
{
    return static_cast<ToposPort>((static_cast<int>(port) + 4) % 8);
}

inline QString portName(ToposPort port)
{
    switch (port) {
    case ToposPort::North:
        return QStringLiteral("N");
    case ToposPort::NorthEast:
        return QStringLiteral("NE");
    case ToposPort::East:
        return QStringLiteral("E");
    case ToposPort::SouthEast:
        return QStringLiteral("SE");
    case ToposPort::South:
        return QStringLiteral("S");
    case ToposPort::SouthWest:
        return QStringLiteral("SW");
    case ToposPort::West:
        return QStringLiteral("W");
    case ToposPort::NorthWest:
        return QStringLiteral("NW");
    }
    Q_UNREACHABLE();
}

inline std::optional<ToposPort> parsePort(QStringView text)
{
    const QString value = text.toString().trimmed().toUpper();
    if (value == QLatin1String("N")) return ToposPort::North;
    if (value == QLatin1String("NE")) return ToposPort::NorthEast;
    if (value == QLatin1String("E")) return ToposPort::East;
    if (value == QLatin1String("SE")) return ToposPort::SouthEast;
    if (value == QLatin1String("S")) return ToposPort::South;
    if (value == QLatin1String("SW")) return ToposPort::SouthWest;
    if (value == QLatin1String("W")) return ToposPort::West;
    if (value == QLatin1String("NW")) return ToposPort::NorthWest;
    return std::nullopt;
}

inline ToposPort quantizeDirection(const QPointF &vector)
{
    if (qFuzzyIsNull(vector.x()) && qFuzzyIsNull(vector.y())) {
        return ToposPort::East;
    }
    qreal angle = qRadiansToDegrees(std::atan2(vector.y(), vector.x()));
    if (angle < 0) {
        angle += 360.0;
    }
    const int sector = qRound(angle / 45.0) % 8;
    // Mathematical angles are E,SE,S,SW,W,NW,N,NE in screen coordinates.
    constexpr ToposPort ports[] = {
        ToposPort::East,
        ToposPort::SouthEast,
        ToposPort::South,
        ToposPort::SouthWest,
        ToposPort::West,
        ToposPort::NorthWest,
        ToposPort::North,
        ToposPort::NorthEast,
    };
    return ports[sector];
}

inline QPointF applyTransport(const QPointF &vector, const ToposTransport &transport)
{
    QPointF result = vector;
    if (transport.mirrored) {
        result.setX(-result.x());
    }
    const qreal angle = qDegreesToRadians(transport.rotationSteps * 45.0);
    const qreal c = std::cos(angle);
    const qreal s = std::sin(angle);
    return QPointF(result.x() * c - result.y() * s,
                   result.x() * s + result.y() * c);
}

inline ToposTransport composeTransport(const ToposTransport &a, const ToposTransport &b)
{
    // Dihedral-group composition. Apply a first, then b.
    ToposTransport result;
    result.mirrored = a.mirrored != b.mirrored;
    const int signedA = b.mirrored ? -a.rotationSteps : a.rotationSteps;
    result.rotationSteps = (signedA + b.rotationSteps) % 8;
    if (result.rotationSteps < 0) {
        result.rotationSteps += 8;
    }
    return result;
}

} // namespace KWin
