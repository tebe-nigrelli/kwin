/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "toposmanager.h"

#include "toposdbusinterface.h"
#include "virtualdesktops.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>

#include <algorithm>
#include <cmath>

namespace KWin
{

namespace
{
constexpr int s_maxCrossingsPerUpdate = 32;
constexpr qreal s_blockedMaximum = 0.15;
// Diagonal traversal should require a deliberate diagonal gesture.  The old
// 22.5 degree sectors made slightly imperfect horizontal/vertical swipes jump
// into a diagonal edge too easily.
constexpr qreal s_diagonalAxisRatio = 0.72;
// Keep the current 45-degree sector until the pointer is roughly 12 degrees
// past its nominal 22.5-degree boundary.
constexpr qreal s_directionHysteresisAlignment = 0.8241261886220157; // cos(34.5 degrees)

QString canonicalBuiltinName(const QString &name)
{
    const QString key = name.trimmed().toLower();
    if (key == QLatin1String("base grid") || key == QLatin1String("base") || key == QLatin1String("grid")) {
        return QStringLiteral("Base Grid");
    }
    if (key == QLatin1String("torus") || key == QLatin1String("donut")) {
        return QStringLiteral("Torus");
    }
    if (key == QLatin1String("cylinder x") || key == QLatin1String("cylinder-x")) {
        return QStringLiteral("Cylinder X");
    }
    if (key == QLatin1String("cylinder y") || key == QLatin1String("cylinder-y")) {
        return QStringLiteral("Cylinder Y");
    }
    if (key == QLatin1String("sphere")) {
        return QStringLiteral("Sphere");
    }
    return QString();
}

QString escapeProfileString(QString value)
{
    value.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    value.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    value.replace(QLatin1Char('\n'), QStringLiteral("\\n"));
    return value;
}

QString unescapeProfileString(const QString &value, bool *ok)
{
    QString result;
    result.reserve(value.size());
    bool escaped = false;
    for (QChar ch : value) {
        if (escaped) {
            if (ch == QLatin1Char('n')) {
                result += QLatin1Char('\n');
            } else if (ch == QLatin1Char('\\') || ch == QLatin1Char('"')) {
                result += ch;
            } else {
                *ok = false;
                return {};
            }
            escaped = false;
        } else if (ch == QLatin1Char('\\')) {
            escaped = true;
        } else {
            result += ch;
        }
    }
    if (escaped) {
        *ok = false;
        return {};
    }
    *ok = true;
    return result;
}

QJsonObject transportJson(const ToposTransport &transport)
{
    return QJsonObject{{QStringLiteral("rotate"), transport.rotationSteps},
                       {QStringLiteral("mirror"), transport.mirrored}};
}

QJsonObject overrideJson(const ToposEndpoint &endpoint, const std::optional<ToposArc> &arc)
{
    QJsonObject object{{QStringLiteral("source"), endpoint.desktopId},
                       {QStringLiteral("port"), portName(endpoint.port)}};
    if (!arc) {
        object.insert(QStringLiteral("blocked"), true);
    } else {
        object.insert(QStringLiteral("target"), arc->targetDesktopId);
        object.insert(QStringLiteral("transport"), transportJson(arc->transport));
    }
    return object;
}

ToposTransport inverseTransport(const ToposTransport &transport)
{
    ToposTransport result;
    result.mirrored = transport.mirrored;
    result.rotationSteps = transport.mirrored ? transport.rotationSteps : -transport.rotationSteps;
    result.rotationSteps %= 8;
    if (result.rotationSteps < 0) {
        result.rotationSteps += 8;
    }
    return result;
}

qreal dot(const QPointF &a, const QPointF &b)
{
    return a.x() * b.x() + a.y() * b.y();
}

qreal length(const QPointF &v)
{
    return std::hypot(v.x(), v.y());
}

} // namespace

ToposManager::ToposManager(VirtualDesktopManager *desktops)
    : QObject(desktops)
    , m_desktops(desktops)
    , m_profileWatcher(std::make_unique<QFileSystemWatcher>())
{
    connect(m_desktops, &VirtualDesktopManager::desktopAdded, this, [this](VirtualDesktop *desktop) {
        connect(desktop, &VirtualDesktop::nameChanged, this, &ToposManager::handleDesktopStructureChanged);
        handleDesktopStructureChanged();
    });
    connect(m_desktops, &VirtualDesktopManager::desktopRemoved, this, [this](VirtualDesktop *) {
        handleDesktopRemoved();
    });
    connect(m_desktops, &VirtualDesktopManager::desktopMoved, this, [this](VirtualDesktop *, int) {
        handleDesktopStructureChanged();
    });
    connect(m_desktops, &VirtualDesktopManager::layoutChanged, this, [this]() {
        handleDesktopStructureChanged();
    });
    connect(m_desktops, &VirtualDesktopManager::rowsChanged, this, [this]() {
        handleDesktopStructureChanged();
    });
    connect(m_profileWatcher.get(), &QFileSystemWatcher::directoryChanged, this, [this]() {
        rescanProfiles();
    });
    connect(m_profileWatcher.get(), &QFileSystemWatcher::fileChanged, this, [this]() {
        rescanProfiles();
    });
}

ToposManager::~ToposManager() = default;

void ToposManager::initialize()
{
    if (m_ready) {
        return;
    }

    for (VirtualDesktop *desktop : m_desktops->desktops()) {
        connect(desktop, &VirtualDesktop::nameChanged, this, &ToposManager::handleDesktopStructureChanged, Qt::UniqueConnection);
    }

    loadSettings();
    QDir().mkpath(profileDirectory());
    QDir().mkpath(QFileInfo(historyPath()).absolutePath());
    rescanProfiles();

    QSettings settings(settingsPath(), QSettings::IniFormat);
    const QString lastProfile = settings.value(QStringLiteral("State/LastProfile"), QStringLiteral("Base Grid")).toString();
    QString error;
    ToposOverrideMap startup;
    const QString builtin = canonicalBuiltinName(lastProfile);
    if (!builtin.isEmpty()) {
        startup = builtinOverrides(builtin, &error);
        if (error.isEmpty()) {
            m_lastLoadedProfile = builtin;
        }
    } else if (m_profiles.contains(lastProfile) && m_profiles.value(lastProfile).compatible) {
        startup = m_profiles.value(lastProfile).overrides;
        m_lastLoadedProfile = lastProfile;
    } else {
        m_lastLoadedProfile = QStringLiteral("Base Grid");
    }
    m_overrides = startup;
    updateDerivedState();

    importPersistentHistory();
    if (m_history.isEmpty() || m_history.constLast().overrides != m_overrides) {
        m_history.append(HistoryEntry{QStringLiteral("Startup"), m_overrides});
    }
    m_historyCursor = m_history.size() - 1;
    capHistory();

    m_dbus = std::make_unique<ToposDBusInterface>(this);
    m_ready = true;
    Q_EMIT readyChanged();
    bumpRevision();
}

bool ToposManager::isReady() const
{
    return m_ready;
}

qulonglong ToposManager::revision() const
{
    return m_revision;
}

ToposOverrideMap ToposManager::overrides() const
{
    return m_overrides;
}

ToposResolvedArc ToposManager::resolve(VirtualDesktop *desktop, ToposPort port, bool wrap) const
{
    if (!desktop) {
        desktop = m_desktops->currentDesktop();
    }
    if (!desktop) {
        return {};
    }

    const ToposEndpoint endpoint{desktop->id(), port};
    const auto overrideIt = m_overrides.constFind(endpoint);
    if (overrideIt != m_overrides.cend()) {
        if (!overrideIt.value()) {
            return ToposResolvedArc{.exists = false, .custom = true, .target = nullptr, .transport = {}};
        }
        VirtualDesktop *target = m_desktops->desktopForId(overrideIt.value()->targetDesktopId);
        if (!target) {
            return ToposResolvedArc{.exists = false, .custom = true, .target = nullptr, .transport = {}};
        }
        return ToposResolvedArc{.exists = true,
                                .custom = true,
                                .target = target,
                                .transport = overrideIt.value()->transport};
    }

    VirtualDesktop *target = nullptr;
    switch (port) {
    case ToposPort::North:
        target = m_desktops->basisNeighbor(desktop, VirtualDesktopManager::Direction::Up, wrap);
        break;
    case ToposPort::East:
        target = m_desktops->basisNeighbor(desktop, VirtualDesktopManager::Direction::Right, wrap);
        break;
    case ToposPort::South:
        target = m_desktops->basisNeighbor(desktop, VirtualDesktopManager::Direction::Down, wrap);
        break;
    case ToposPort::West:
        target = m_desktops->basisNeighbor(desktop, VirtualDesktopManager::Direction::Left, wrap);
        break;
    case ToposPort::NorthEast:
    case ToposPort::SouthEast:
    case ToposPort::SouthWest:
    case ToposPort::NorthWest:
        target = basisDiagonal(desktop, port, wrap, wrap);
        break;
    }

    if (!target || target == desktop) {
        return {};
    }
    return ToposResolvedArc{.exists = true, .custom = false, .target = target, .transport = {}};
}

VirtualDesktop *ToposManager::neighbor(VirtualDesktop *desktop, ToposPort port, bool wrap) const
{
    if (!desktop) {
        desktop = m_desktops->currentDesktop();
    }
    const ToposResolvedArc arc = resolve(desktop, port, wrap);
    return arc.exists ? arc.target : desktop;
}

QString ToposManager::activeProfile() const
{
    return m_activeProfile;
}

QString ToposManager::lastLoadedProfile() const
{
    return m_lastLoadedProfile;
}

bool ToposManager::isDirty() const
{
    return m_dirty;
}

QStringList ToposManager::listBuiltins() const
{
    return {QStringLiteral("Base Grid"), QStringLiteral("Torus"), QStringLiteral("Cylinder X"), QStringLiteral("Cylinder Y"), QStringLiteral("Sphere")};
}

QStringList ToposManager::listProfiles() const
{
    QStringList names;
    for (auto it = m_profiles.cbegin(); it != m_profiles.cend(); ++it) {
        if (it->valid && it->compatible) {
            names << it.key();
        }
    }
    names.sort(Qt::CaseInsensitive);
    return names;
}

QStringList ToposManager::listAllProfiles() const
{
    QStringList names = m_profiles.keys();
    names.sort(Qt::CaseInsensitive);
    return names;
}

bool ToposManager::mutate(const QString &label, const std::function<bool(QString *)> &operation, QString *error)
{
    if (!m_ready) {
        if (error) {
            *error = QStringLiteral("Topos is not ready");
        }
        return false;
    }
    const ToposOverrideMap before = m_overrides;
    QString localError;
    if (!operation(&localError)) {
        m_overrides = before;
        if (error) {
            *error = localError;
        }
        return false;
    }
    if (before == m_overrides) {
        return true;
    }
    pushHistory(label);
    bumpRevision();
    updateDerivedState();
    saveHistory();
    return true;
}

bool ToposManager::reset(QString *error)
{
    return mutate(QStringLiteral("Reset to Base Grid"), [this](QString *) {
        m_overrides.clear();
        m_lastLoadedProfile = QStringLiteral("Base Grid");
        QSettings settings(settingsPath(), QSettings::IniFormat);
        settings.setValue(QStringLiteral("State/LastProfile"), m_lastLoadedProfile);
        return true;
    }, error);
}

bool ToposManager::applyBuiltin(const QString &name, QString *error)
{
    const QString canonical = canonicalBuiltinName(name);
    if (canonical.isEmpty()) {
        if (error) {
            *error = QStringLiteral("Unknown builtin: %1").arg(name);
        }
        return false;
    }
    QString buildError;
    const ToposOverrideMap overrides = builtinOverrides(canonical, &buildError);
    if (!buildError.isEmpty()) {
        if (error) {
            *error = buildError;
        }
        return false;
    }
    return mutate(QStringLiteral("Apply %1").arg(canonical), [this, overrides, canonical](QString *) {
        m_overrides = overrides;
        m_lastLoadedProfile = canonical;
        QSettings settings(settingsPath(), QSettings::IniFormat);
        settings.setValue(QStringLiteral("State/LastProfile"), canonical);
        return true;
    }, error);
}

bool ToposManager::loadProfile(const QString &name, QString *error)
{
    const auto it = m_profiles.constFind(name);
    if (it == m_profiles.cend()) {
        if (error) {
            *error = QStringLiteral("Profile not found: %1").arg(name);
        }
        return false;
    }
    if (!it->valid) {
        if (error) {
            *error = it->error;
        }
        return false;
    }
    if (!it->compatible) {
        if (error) {
            *error = QStringLiteral("Profile is incompatible with the current desktop names");
        }
        return false;
    }
    const ToposOverrideMap overrides = it->overrides;
    return mutate(QStringLiteral("Load %1").arg(name), [this, overrides, name](QString *) {
        m_overrides = overrides;
        m_lastLoadedProfile = name;
        QSettings settings(settingsPath(), QSettings::IniFormat);
        settings.setValue(QStringLiteral("State/LastProfile"), name);
        return true;
    }, error);
}

bool ToposManager::validProfileName(const QString &name, QString *error) const
{
    if (name.trimmed().isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QChar::Null)) {
        if (error) {
            *error = QStringLiteral("Profile name must be non-empty and may not contain '/' or NUL");
        }
        return false;
    }
    return true;
}

bool ToposManager::saveProfile(const QString &name, bool overwrite, QString *error)
{
    if (!validProfileName(name, error)) {
        return false;
    }
    if (!canonicalBuiltinName(name).isEmpty()) {
        if (error) {
            *error = QStringLiteral("Builtin profiles are read-only; choose a different name");
        }
        return false;
    }
    const QString path = profileDirectory() + QLatin1Char('/') + name + QStringLiteral(".topos");
    if (QFileInfo::exists(path) && !overwrite) {
        if (error) {
            *error = QStringLiteral("Profile already exists: %1").arg(name);
        }
        return false;
    }
    if (!writeProfile(path, error)) {
        return false;
    }
    m_lastLoadedProfile = name;
    QSettings settings(settingsPath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("State/LastProfile"), name);
    rescanProfiles();
    updateDerivedState();
    return true;
}

bool ToposManager::renameProfile(const QString &oldName, const QString &newName, bool overwrite, QString *error)
{
    if (!validProfileName(newName, error)) {
        return false;
    }
    if (!canonicalBuiltinName(newName).isEmpty()) {
        if (error) {
            *error = QStringLiteral("Builtin profiles are read-only");
        }
        return false;
    }
    const auto oldIt = m_profiles.constFind(oldName);
    if (oldIt == m_profiles.cend()) {
        if (error) {
            *error = QStringLiteral("Profile not found: %1").arg(oldName);
        }
        return false;
    }
    const QString newPath = profileDirectory() + QLatin1Char('/') + newName + QStringLiteral(".topos");
    if (QFileInfo::exists(newPath)) {
        if (!overwrite) {
            if (error) {
                *error = QStringLiteral("Profile already exists: %1").arg(newName);
            }
            return false;
        }
        if (!QFile::remove(newPath)) {
            if (error) {
                *error = QStringLiteral("Could not replace %1").arg(newName);
            }
            return false;
        }
    }
    if (!QFile::rename(oldIt->path, newPath)) {
        if (error) {
            *error = QStringLiteral("Could not rename profile");
        }
        return false;
    }
    if (m_lastLoadedProfile == oldName) {
        m_lastLoadedProfile = newName;
        QSettings settings(settingsPath(), QSettings::IniFormat);
        settings.setValue(QStringLiteral("State/LastProfile"), newName);
    }
    rescanProfiles();
    updateDerivedState();
    return true;
}

bool ToposManager::deleteProfile(const QString &name, QString *error)
{
    const auto it = m_profiles.constFind(name);
    if (it == m_profiles.cend()) {
        if (error) {
            *error = QStringLiteral("Profile not found: %1").arg(name);
        }
        return false;
    }
    if (!QFile::remove(it->path)) {
        if (error) {
            *error = QStringLiteral("Could not delete profile: %1").arg(name);
        }
        return false;
    }
    rescanProfiles();
    updateDerivedState();
    return true;
}

VirtualDesktop *ToposManager::resolveDesktopSelector(const QString &selector, QString *error) const
{
    const QString value = selector.trimmed();
    if (value == QLatin1String("@current")) {
        return m_desktops->currentDesktop();
    }
    if (VirtualDesktop *desktop = m_desktops->desktopForId(value)) {
        return desktop;
    }

    bool positionOk = false;
    const uint position = value.toUInt(&positionOk);
    if (positionOk && position >= 1 && position <= m_desktops->count()) {
        return m_desktops->desktopForX11Id(position);
    }

    QString baseName = value;
    int requestedOccurrence = 1;
    const QRegularExpression occurrenceExpression(QStringLiteral("^(.*)#([1-9][0-9]*)$"));
    const QRegularExpressionMatch occurrenceMatch = occurrenceExpression.match(value);
    if (occurrenceMatch.hasMatch()) {
        baseName = occurrenceMatch.captured(1);
        requestedOccurrence = occurrenceMatch.captured(2).toInt();
    }

    int occurrence = 0;
    VirtualDesktop *match = nullptr;
    int totalMatches = 0;
    for (VirtualDesktop *desktop : m_desktops->desktops()) {
        if (desktop->name() == baseName) {
            ++totalMatches;
            ++occurrence;
            if (occurrence == requestedOccurrence) {
                match = desktop;
            }
        }
    }
    if (match && (occurrenceMatch.hasMatch() || totalMatches == 1)) {
        return match;
    }
    if (totalMatches > 1 && !occurrenceMatch.hasMatch()) {
        if (error) {
            *error = QStringLiteral("Desktop name is duplicated; use %1#N").arg(baseName);
        }
        return nullptr;
    }
    if (error) {
        *error = QStringLiteral("Desktop not found: %1").arg(selector);
    }
    return nullptr;
}

bool ToposManager::setArc(const QString &sourceSelector, ToposPort port, const QString &targetSelector,
                          bool bidirectional, ToposTransport transport, QString *error)
{
    QString localError;
    VirtualDesktop *source = resolveDesktopSelector(sourceSelector, &localError);
    if (!source) {
        if (error) *error = localError;
        return false;
    }
    VirtualDesktop *target = resolveDesktopSelector(targetSelector, &localError);
    if (!target) {
        if (error) *error = localError;
        return false;
    }
    transport.rotationSteps %= 8;
    if (transport.rotationSteps < 0) transport.rotationSteps += 8;

    const ToposEndpoint endpoint{source->id(), port};
    const ToposEndpoint reverseEndpoint{target->id(), oppositePort(port)};
    std::optional<ToposEndpoint> previousReverseEndpoint;
    const auto currentIt = m_overrides.constFind(endpoint);
    if (currentIt != m_overrides.cend() && currentIt.value()) {
        const ToposEndpoint oldReverse{currentIt.value()->targetDesktopId, oppositePort(port)};
        const auto oldReverseIt = m_overrides.constFind(oldReverse);
        if (oldReverseIt != m_overrides.cend()
            && oldReverseIt.value()
            && oldReverseIt.value()->targetDesktopId == source->id()) {
            previousReverseEndpoint = oldReverse;
        }
    }
    if (bidirectional) {
        const auto reverseIt = m_overrides.constFind(reverseEndpoint);
        if (reverseIt != m_overrides.cend()) {
            const bool same = reverseIt.value() && reverseIt.value()->targetDesktopId == source->id();
            if (!same) {
                if (error) {
                    *error = QStringLiteral("Reverse port %1.%2 already has an explicit override")
                                 .arg(target->name(), portName(reverseEndpoint.port));
                }
                return false;
            }
        }
    }

    const QString label = bidirectional
        ? QStringLiteral("Link %1.%2 ↔ %3").arg(source->name(), portName(port), target->name())
        : QStringLiteral("Link %1.%2 → %3").arg(source->name(), portName(port), target->name());
    return mutate(label, [this, endpoint, reverseEndpoint, previousReverseEndpoint, source, target, bidirectional, transport](QString *) {
        if (previousReverseEndpoint && (!bidirectional || *previousReverseEndpoint != reverseEndpoint)) {
            m_overrides.remove(*previousReverseEndpoint);
        }
        m_overrides.insert(endpoint, ToposArc{target->id(), transport});
        if (bidirectional) {
            m_overrides.insert(reverseEndpoint, ToposArc{source->id(), {}});
        }
        return true;
    }, error);
}

bool ToposManager::blockArc(const QString &sourceSelector, ToposPort port, QString *error)
{
    QString localError;
    VirtualDesktop *source = resolveDesktopSelector(sourceSelector, &localError);
    if (!source) {
        if (error) *error = localError;
        return false;
    }
    const ToposEndpoint endpoint{source->id(), port};
    return mutate(QStringLiteral("Block %1.%2").arg(source->name(), portName(port)), [this, endpoint](QString *) {
        m_overrides.insert(endpoint, std::nullopt);
        return true;
    }, error);
}

bool ToposManager::restoreArc(const QString &sourceSelector, ToposPort port, QString *error)
{
    QString localError;
    VirtualDesktop *source = resolveDesktopSelector(sourceSelector, &localError);
    if (!source) {
        if (error) *error = localError;
        return false;
    }
    const ToposEndpoint endpoint{source->id(), port};
    return mutate(QStringLiteral("Restore %1.%2 to basis").arg(source->name(), portName(port)), [this, endpoint](QString *) {
        m_overrides.remove(endpoint);
        return true;
    }, error);
}

bool ToposManager::collapseVertex(const QString &victimSelector, const QString &representativeSelector, QString *error)
{
    QString localError;
    VirtualDesktop *victim = resolveDesktopSelector(victimSelector, &localError);
    if (!victim) {
        if (error) *error = localError;
        return false;
    }
    VirtualDesktop *representative = resolveDesktopSelector(representativeSelector, &localError);
    if (!representative) {
        if (error) *error = localError;
        return false;
    }
    if (victim == representative) {
        if (error) *error = QStringLiteral("Victim and representative are the same desktop");
        return false;
    }

    return mutate(QStringLiteral("Collapse %1 into %2").arg(victim->name(), representative->name()), [this, victim, representative](QString *) {
        const QList<VirtualDesktop *> desktops = m_desktops->desktops();
        for (VirtualDesktop *source : desktops) {
            for (int p = 0; p < 8; ++p) {
                const ToposPort port = static_cast<ToposPort>(p);
                const ToposResolvedArc arc = resolve(source, port, m_desktops->isNavigationWrappingAround());
                if (arc.exists && arc.target == victim) {
                    m_overrides.insert(ToposEndpoint{source->id(), port}, ToposArc{representative->id(), arc.transport});
                }
            }
        }
        for (int p = 0; p < 8; ++p) {
            m_overrides.insert(ToposEndpoint{victim->id(), static_cast<ToposPort>(p)}, std::nullopt);
        }
        return true;
    }, error);
}

void ToposManager::setOverrides(const ToposOverrideMap &overrides, bool bump)
{
    if (m_overrides == overrides) {
        return;
    }
    m_overrides = overrides;
    if (bump) {
        bumpRevision();
        updateDerivedState();
    }
}

void ToposManager::pushHistory(const QString &label)
{
    if (m_historyCursor + 1 < m_history.size()) {
        m_history.resize(m_historyCursor + 1);
    }
    if (!m_history.isEmpty() && m_history.constLast().overrides == m_overrides) {
        m_history.last().label = label;
        m_historyCursor = m_history.size() - 1;
        Q_EMIT historyChanged();
        return;
    }
    m_history.append(HistoryEntry{label, m_overrides});
    m_historyCursor = m_history.size() - 1;
    capHistory();
    Q_EMIT historyChanged();
}

void ToposManager::capHistory()
{
    const int maximumStates = std::max(1, m_historyLimit + 1);
    if (m_history.size() <= maximumStates) {
        return;
    }
    const int removeCount = m_history.size() - maximumStates;
    m_history.remove(0, removeCount);
    m_historyCursor = std::max(0, m_historyCursor - removeCount);
}

void ToposManager::applyHistoryEntry(int index)
{
    if (index < 0 || index >= m_history.size()) {
        return;
    }
    m_historyCursor = index;
    setOverrides(m_history[index].overrides);
    Q_EMIT historyChanged();
    saveHistory();
}

bool ToposManager::undo(int count)
{
    if (count < 1 || !canUndo()) {
        return false;
    }
    applyHistoryEntry(std::max(0, m_historyCursor - count));
    return true;
}

bool ToposManager::redo(int count)
{
    if (count < 1 || !canRedo()) {
        return false;
    }
    applyHistoryEntry(std::min(static_cast<int>(m_history.size()) - 1, m_historyCursor + count));
    return true;
}

void ToposManager::clearHistory()
{
    m_history = {HistoryEntry{QStringLiteral("Current topology"), m_overrides}};
    m_historyCursor = 0;
    saveHistory();
    Q_EMIT historyChanged();
}

bool ToposManager::gotoHistory(int index)
{
    if (index < 0 || index >= m_history.size() || index == m_historyCursor) {
        return false;
    }
    applyHistoryEntry(index);
    return true;
}

bool ToposManager::canUndo() const
{
    return m_historyCursor > 0;
}

bool ToposManager::canRedo() const
{
    return m_historyCursor >= 0 && m_historyCursor + 1 < m_history.size();
}

int ToposManager::historyLimit() const
{
    return m_historyLimit;
}

void ToposManager::setHistoryLimit(int limit)
{
    limit = std::clamp(limit, 1, 1000);
    if (m_historyLimit == limit) return;
    m_historyLimit = limit;
    capHistory();
    saveSettings();
    saveHistory();
    Q_EMIT settingsChanged();
    Q_EMIT historyChanged();
}

bool ToposManager::persistHistory() const
{
    return m_persistHistory;
}

void ToposManager::setPersistHistory(bool enabled)
{
    if (m_persistHistory == enabled) return;
    m_persistHistory = enabled;
    saveSettings();
    if (enabled) {
        saveHistory();
    } else {
        QFile::remove(historyPath());
    }
    Q_EMIT settingsChanged();
}

int ToposManager::gestureDistance() const
{
    return m_gestureDistance;
}

void ToposManager::setGestureDistance(int distance)
{
    distance = std::clamp(distance, 50, 2000);
    if (m_gestureDistance == distance) return;
    m_gestureDistance = distance;
    saveSettings();
    Q_EMIT settingsChanged();
}

qreal ToposManager::settleThreshold() const
{
    return m_settleThreshold;
}

void ToposManager::setSettleThreshold(qreal threshold)
{
    threshold = std::clamp(threshold, 0.05, 0.95);
    if (qFuzzyCompare(m_settleThreshold, threshold)) return;
    m_settleThreshold = threshold;
    saveSettings();
    Q_EMIT settingsChanged();
}

bool ToposManager::showHandles() const
{
    return m_showHandles;
}

void ToposManager::setShowHandles(bool show)
{
    if (m_showHandles == show) return;
    m_showHandles = show;
    saveSettings();
    Q_EMIT settingsChanged();
}

bool ToposManager::showBridgePreview() const
{
    return m_showBridgePreview;
}

void ToposManager::setShowBridgePreview(bool show)
{
    if (m_showBridgePreview == show) return;
    m_showBridgePreview = show;
    saveSettings();
    Q_EMIT settingsChanged();
}

QVariantMap ToposManager::edgeInfo(const QString &desktopId, int portValue) const
{
    QVariantMap result;
    VirtualDesktop *desktop = m_desktops->desktopForId(desktopId);
    if (!desktop || portValue < 0 || portValue > 7) {
        return result;
    }
    const ToposPort port = static_cast<ToposPort>(portValue);
    const ToposEndpoint endpoint{desktopId, port};
    const auto it = m_overrides.constFind(endpoint);
    const ToposResolvedArc effective = resolve(desktop, port, m_desktops->isNavigationWrappingAround());
    result.insert(QStringLiteral("port"), portValue);
    result.insert(QStringLiteral("portName"), portName(port));
    result.insert(QStringLiteral("custom"), it != m_overrides.cend());
    result.insert(QStringLiteral("blocked"), it != m_overrides.cend() && !it.value());
    result.insert(QStringLiteral("exists"), effective.exists);
    result.insert(QStringLiteral("state"), it == m_overrides.cend() ? QStringLiteral("inherited") : (it.value() ? QStringLiteral("custom") : QStringLiteral("blocked")));
    if (effective.exists && effective.target) {
        result.insert(QStringLiteral("targetId"), effective.target->id());
        result.insert(QStringLiteral("targetName"), effective.target->name());
        result.insert(QStringLiteral("rotationSteps"), effective.transport.rotationSteps);
        result.insert(QStringLiteral("mirrored"), effective.transport.mirrored);
        const ToposEndpoint reverse{effective.target->id(), oppositePort(port)};
        const auto reverseIt = m_overrides.constFind(reverse);
        result.insert(QStringLiteral("bidirectional"), reverseIt != m_overrides.cend()
            && reverseIt.value()
            && reverseIt.value()->targetDesktopId == desktopId);

        const ToposResolvedArc reverseEffective = resolve(effective.target, oppositePort(port), m_desktops->isNavigationWrappingAround());
        result.insert(QStringLiteral("effectiveBidirectional"), reverseEffective.exists
            && reverseEffective.target
            && reverseEffective.target->id() == desktopId);
    }
    return result;
}

void ToposManager::selectPort(const QString &desktopId, int port)
{
    if (port < 0 || port > 7 || !m_desktops->desktopForId(desktopId)) {
        return;
    }
    m_selectedDesktop = desktopId;
    m_selectedPort = port;
    Q_EMIT selectionChanged();
}

void ToposManager::blockSelectedPort()
{
    if (m_selectedDesktop.isEmpty() || m_selectedPort < 0) return;
    QString ignored;
    blockArc(m_selectedDesktop, static_cast<ToposPort>(m_selectedPort), &ignored);
}

void ToposManager::linkSelectedTo(const QString &desktopId, bool bidirectional)
{
    if (m_selectedDesktop.isEmpty() || m_selectedPort < 0) return;
    QString ignored;
    setArc(m_selectedDesktop, static_cast<ToposPort>(m_selectedPort), desktopId, bidirectional, {}, &ignored);
    cancelSelection();
}

void ToposManager::unlinkPort(const QString &desktopId, int portValue)
{
    if (portValue < 0 || portValue > 7) {
        return;
    }
    VirtualDesktop *source = m_desktops->desktopForId(desktopId);
    if (!source) {
        return;
    }

    const ToposPort port = static_cast<ToposPort>(portValue);
    const ToposResolvedArc arc = resolve(source, port, m_desktops->isNavigationWrappingAround());
    if (!arc.exists || !arc.target) {
        return;
    }

    const ToposEndpoint endpoint{desktopId, port};
    const ToposEndpoint reverseEndpoint{arc.target->id(), oppositePort(port)};
    const auto reverseIt = m_overrides.constFind(reverseEndpoint);
    const bool explicitPair = reverseIt != m_overrides.cend()
        && reverseIt.value()
        && reverseIt.value()->targetDesktopId == desktopId;

    const QString label = QStringLiteral("Unlink %1.%2").arg(source->name(), portName(port));
    QString ignored;
    mutate(label, [this, endpoint, reverseEndpoint, explicitPair](QString *) {
        m_overrides.insert(endpoint, std::nullopt);
        if (explicitPair) {
            m_overrides.insert(reverseEndpoint, std::nullopt);
        }
        return true;
    }, &ignored);

    if (m_selectedDesktop == desktopId && m_selectedPort == portValue) {
        cancelSelection();
    }
}

void ToposManager::restorePort(const QString &desktopId, int port)
{
    if (port < 0 || port > 7) return;
    QString ignored;
    restoreArc(desktopId, static_cast<ToposPort>(port), &ignored);
}

void ToposManager::cancelSelection()
{
    if (m_selectedDesktop.isEmpty() && m_selectedPort == -1) return;
    m_selectedDesktop.clear();
    m_selectedPort = -1;
    Q_EMIT selectionChanged();
}

QStringList ToposManager::compatibleProfiles() const
{
    return listProfiles();
}

QString ToposManager::selectedDesktop() const
{
    return m_selectedDesktop;
}

int ToposManager::selectedPort() const
{
    return m_selectedPort;
}

QString ToposManager::stateJson() const
{
    QJsonObject object{
        {QStringLiteral("apiVersion"), ToposApiVersion},
        {QStringLiteral("ready"), m_ready},
        {QStringLiteral("revision"), static_cast<qint64>(m_revision)},
        {QStringLiteral("activeProfile"), m_activeProfile},
        {QStringLiteral("lastLoadedProfile"), m_lastLoadedProfile},
        {QStringLiteral("dirty"), m_dirty},
        {QStringLiteral("canUndo"), canUndo()},
        {QStringLiteral("canRedo"), canRedo()},
        {QStringLiteral("historyLimit"), m_historyLimit},
        {QStringLiteral("persistHistory"), m_persistHistory},
        {QStringLiteral("gestureDistance"), m_gestureDistance},
        {QStringLiteral("settleThreshold"), m_settleThreshold},
        {QStringLiteral("showHandles"), m_showHandles},
        {QStringLiteral("showBridgePreview"), m_showBridgePreview},
    };
    QJsonArray names;
    for (const QString &name : currentSignature()) names.append(name);
    object.insert(QStringLiteral("desktopNames"), names);
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

QString ToposManager::graphJson() const
{
    QJsonObject root;
    QJsonArray overridesArray;
    for (auto it = m_overrides.cbegin(); it != m_overrides.cend(); ++it) {
        overridesArray.append(overrideJson(it.key(), it.value()));
    }
    root.insert(QStringLiteral("overrides"), overridesArray);

    QJsonArray effective;
    for (VirtualDesktop *source : m_desktops->desktops()) {
        for (int p = 0; p < 8; ++p) {
            const ToposPort port = static_cast<ToposPort>(p);
            const ToposResolvedArc arc = resolve(source, port, m_desktops->isNavigationWrappingAround());
            QJsonObject edge{{QStringLiteral("source"), source->id()},
                             {QStringLiteral("sourceName"), source->name()},
                             {QStringLiteral("port"), portName(port)},
                             {QStringLiteral("exists"), arc.exists},
                             {QStringLiteral("custom"), arc.custom}};
            if (arc.exists && arc.target) {
                edge.insert(QStringLiteral("target"), arc.target->id());
                edge.insert(QStringLiteral("targetName"), arc.target->name());
                edge.insert(QStringLiteral("transport"), transportJson(arc.transport));
            }
            effective.append(edge);
        }
    }
    root.insert(QStringLiteral("effective"), effective);
    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

QString ToposManager::historyJson() const
{
    QJsonObject root;
    root.insert(QStringLiteral("cursor"), m_historyCursor);
    QJsonArray entries;
    for (int i = 0; i < m_history.size(); ++i) {
        QJsonObject entry{{QStringLiteral("index"), i},
                          {QStringLiteral("label"), m_history[i].label},
                          {QStringLiteral("current"), i == m_historyCursor}};
        entries.append(entry);
    }
    root.insert(QStringLiteral("entries"), entries);
    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

QString ToposManager::profileDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/topos/topologies");
}

QString ToposManager::settingsPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/toposrc");
}

QString ToposManager::historyPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::StateLocation) + QStringLiteral("/topos/history.json");
}

QStringList ToposManager::currentSignature() const
{
    QStringList names;
    names.reserve(m_desktops->desktops().size());
    for (VirtualDesktop *desktop : m_desktops->desktops()) {
        names << desktop->name();
    }
    return names;
}

bool ToposManager::signaturesCompatible(const QStringList &a, const QStringList &b) const
{
    if (a.size() != b.size()) return false;
    QStringList left = a;
    QStringList right = b;
    left.sort();
    right.sort();
    return left == right;
}

QHash<QString, VirtualDesktop *> ToposManager::aliasMapping(const QStringList &aliases, const QStringList &names, QString *error) const
{
    QHash<QString, VirtualDesktop *> result;
    QHash<QString, int> occurrenceByName;
    const QList<VirtualDesktop *> desktops = m_desktops->desktops();
    for (int i = 0; i < aliases.size(); ++i) {
        const QString &name = names[i];
        const int occurrence = ++occurrenceByName[name];
        int seen = 0;
        VirtualDesktop *match = nullptr;
        for (VirtualDesktop *desktop : desktops) {
            if (desktop->name() == name && ++seen == occurrence) {
                match = desktop;
                break;
            }
        }
        if (!match) {
            if (error) *error = QStringLiteral("Could not map desktop '%1' occurrence %2").arg(name).arg(occurrence);
            return {};
        }
        result.insert(aliases[i], match);
    }
    return result;
}

ToposManager::ProfileEntry ToposManager::parseProfile(const QString &path) const
{
    ProfileEntry entry;
    entry.path = path;
    entry.name = QFileInfo(path).completeBaseName();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        entry.error = QStringLiteral("Cannot read profile");
        return entry;
    }
    const QString content = QString::fromUtf8(file.readAll());
    const QStringList lines = content.split(QLatin1Char('\n'));

    struct PendingArc {
        QString sourceAlias;
        ToposPort port;
        QString op;
        QString targetAlias;
        ToposTransport transport;
        int line = 0;
    };
    QVector<PendingArc> pending;
    QStringList aliases;
    QStringList names;
    QSet<QString> seenAliases;
    bool versionSeen = false;

    const QRegularExpression desktopRe(QStringLiteral(R"re(^desktop\s+(\S+)\s+"((?:\\.|[^"])*)"\s*$)re"));
    const QRegularExpression arcRe(QStringLiteral(R"(^(\S+):(N|NE|E|SE|S|SW|W|NW)\s*(->|<->)\s*(\S+)(?:\s+rotate=(-?\d+))?(?:\s+mirror=(true|false))?\s*$)"), QRegularExpression::CaseInsensitiveOption);

    for (int index = 0; index < lines.size(); ++index) {
        QString line = lines[index].trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) continue;
        if (line == QLatin1String("topos 1")) {
            if (versionSeen) {
                entry.error = QStringLiteral("line %1: duplicate version").arg(index + 1);
                return entry;
            }
            versionSeen = true;
            continue;
        }
        if (line.startsWith(QLatin1String("basis-rows "))) {
            bool ok = false;
            line.mid(11).trimmed().toInt(&ok);
            if (!ok) {
                entry.error = QStringLiteral("line %1: invalid basis-rows").arg(index + 1);
                return entry;
            }
            continue;
        }
        const QRegularExpressionMatch desktopMatch = desktopRe.match(line);
        if (desktopMatch.hasMatch()) {
            const QString alias = desktopMatch.captured(1);
            if (seenAliases.contains(alias)) {
                entry.error = QStringLiteral("line %1: duplicate desktop alias").arg(index + 1);
                return entry;
            }
            bool ok = false;
            const QString name = unescapeProfileString(desktopMatch.captured(2), &ok);
            if (!ok) {
                entry.error = QStringLiteral("line %1: invalid string escape").arg(index + 1);
                return entry;
            }
            seenAliases.insert(alias);
            aliases << alias;
            names << name;
            continue;
        }
        const QRegularExpressionMatch arcMatch = arcRe.match(line);
        if (arcMatch.hasMatch()) {
            const auto port = parsePort(arcMatch.capturedView(2));
            Q_ASSERT(port);
            bool rotationOk = true;
            int rotation = 0;
            if (!arcMatch.captured(5).isEmpty()) {
                rotation = arcMatch.captured(5).toInt(&rotationOk);
            }
            if (!rotationOk || rotation < -1024 || rotation > 1024) {
                entry.error = QStringLiteral("line %1: invalid rotation").arg(index + 1);
                return entry;
            }
            rotation %= 8;
            if (rotation < 0) rotation += 8;
            pending.append(PendingArc{arcMatch.captured(1), *port, arcMatch.captured(3), arcMatch.captured(4),
                                      ToposTransport{rotation, arcMatch.captured(6).compare(QLatin1String("true"), Qt::CaseInsensitive) == 0}, index + 1});
            continue;
        }
        entry.error = QStringLiteral("line %1: unrecognized syntax").arg(index + 1);
        return entry;
    }

    if (!versionSeen) {
        entry.error = QStringLiteral("missing 'topos 1' header");
        return entry;
    }
    entry.signature = names;
    entry.compatible = signaturesCompatible(names, currentSignature());
    if (!entry.compatible) {
        entry.valid = true;
        return entry;
    }

    QString mapError;
    const QHash<QString, VirtualDesktop *> mapping = aliasMapping(aliases, names, &mapError);
    if (!mapError.isEmpty()) {
        entry.error = mapError;
        return entry;
    }
    QSet<ToposEndpoint> defined;
    for (const PendingArc &arc : pending) {
        VirtualDesktop *source = mapping.value(arc.sourceAlias);
        if (!source) {
            entry.error = QStringLiteral("line %1: unknown source alias '%2'").arg(arc.line).arg(arc.sourceAlias);
            return entry;
        }
        const ToposEndpoint endpoint{source->id(), arc.port};
        if (defined.contains(endpoint)) {
            entry.error = QStringLiteral("line %1: duplicate arc definition").arg(arc.line);
            return entry;
        }
        defined.insert(endpoint);
        if (arc.targetAlias == QLatin1String("none")) {
            if (arc.op == QLatin1String("<->")) {
                entry.error = QStringLiteral("line %1: blocked arc cannot be bidirectional").arg(arc.line);
                return entry;
            }
            entry.overrides.insert(endpoint, std::nullopt);
            continue;
        }
        VirtualDesktop *target = mapping.value(arc.targetAlias);
        if (!target) {
            entry.error = QStringLiteral("line %1: unknown target alias '%2'").arg(arc.line).arg(arc.targetAlias);
            return entry;
        }
        entry.overrides.insert(endpoint, ToposArc{target->id(), arc.transport});
        if (arc.op == QLatin1String("<->")) {
            const ToposEndpoint reverse{target->id(), oppositePort(arc.port)};
            if (defined.contains(reverse)) {
                entry.error = QStringLiteral("line %1: reverse port already defined").arg(arc.line);
                return entry;
            }
            defined.insert(reverse);
            entry.overrides.insert(reverse, ToposArc{source->id(), {}});
        }
    }
    entry.valid = true;
    return entry;
}

bool ToposManager::writeProfile(const QString &path, QString *error) const
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (error) *error = QStringLiteral("Could not open profile for writing");
        return false;
    }
    QByteArray output("# Topos profile format 1\ntopos 1\n\n");
    QHash<QString, QString> aliases;
    const QList<VirtualDesktop *> desktops = m_desktops->desktops();
    for (int i = 0; i < desktops.size(); ++i) {
        const QString alias = QString::number(i);
        aliases.insert(desktops[i]->id(), alias);
        output += QStringLiteral("desktop %1 \"%2\"\n").arg(alias, escapeProfileString(desktops[i]->name())).toUtf8();
    }
    output += QStringLiteral("\nbasis-rows %1\n\n").arg(m_desktops->rows()).toUtf8();

    QList<ToposEndpoint> endpoints = m_overrides.keys();
    std::sort(endpoints.begin(), endpoints.end(), [&aliases](const ToposEndpoint &a, const ToposEndpoint &b) {
        const int sourceCompare = QString::compare(aliases.value(a.desktopId), aliases.value(b.desktopId), Qt::CaseSensitive);
        if (sourceCompare != 0) return sourceCompare < 0;
        return static_cast<int>(a.port) < static_cast<int>(b.port);
    });
    for (const ToposEndpoint &endpoint : endpoints) {
        if (!aliases.contains(endpoint.desktopId)) {
            continue;
        }
        const QString sourceAlias = aliases.value(endpoint.desktopId);
        const auto arc = m_overrides.value(endpoint);
        if (!arc) {
            output += QStringLiteral("%1:%2 -> none\n").arg(sourceAlias, portName(endpoint.port)).toUtf8();
        } else {
            const QString targetAlias = aliases.value(arc->targetDesktopId);
            if (targetAlias.isEmpty() && !aliases.contains(arc->targetDesktopId)) continue;
            QString line = QStringLiteral("%1:%2 -> %3").arg(sourceAlias, portName(endpoint.port), targetAlias);
            if (arc->transport.rotationSteps != 0) {
                line += QStringLiteral(" rotate=%1").arg(arc->transport.rotationSteps);
            }
            if (arc->transport.mirrored) {
                line += QStringLiteral(" mirror=true");
            }
            output += (line + QLatin1Char('\n')).toUtf8();
        }
    }
    if (file.write(output) != output.size() || !file.commit()) {
        if (error) *error = QStringLiteral("Could not atomically save profile");
        return false;
    }
    return true;
}

void ToposManager::rescanProfiles()
{
    const QString dirPath = profileDirectory();
    QDir dir(dirPath);
    if (!dir.exists()) {
        QDir().mkpath(dirPath);
    }
    QHash<QString, ProfileEntry> profiles;
    const QFileInfoList files = dir.entryInfoList({QStringLiteral("*.topos")}, QDir::Files, QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &file : files) {
        ProfileEntry entry = parseProfile(file.absoluteFilePath());
        profiles.insert(entry.name, entry);
    }
    m_profiles = profiles;

    const QStringList watched = m_profileWatcher->directories();
    if (!watched.contains(dirPath)) {
        m_profileWatcher->addPath(dirPath);
    }
    updateDerivedState();
    Q_EMIT profilesChanged();
}

VirtualDesktop *ToposManager::basisDiagonal(VirtualDesktop *desktop, ToposPort port, bool wrapX, bool wrapY) const
{
    QPoint coords = m_desktops->grid().gridCoords(desktop);
    if (coords.x() < 0 || coords.y() < 0) return nullptr;
    switch (port) {
    case ToposPort::NorthEast:
        coords += QPoint(1, -1);
        break;
    case ToposPort::SouthEast:
        coords += QPoint(1, 1);
        break;
    case ToposPort::SouthWest:
        coords += QPoint(-1, 1);
        break;
    case ToposPort::NorthWest:
        coords += QPoint(-1, -1);
        break;
    default:
        return nullptr;
    }
    const int width = m_desktops->grid().width();
    const int height = m_desktops->grid().height();
    if (coords.x() < 0 || coords.x() >= width) {
        if (!wrapX || width <= 0) return nullptr;
        coords.setX((coords.x() % width + width) % width);
    }
    if (coords.y() < 0 || coords.y() >= height) {
        if (!wrapY || height <= 0) return nullptr;
        coords.setY((coords.y() % height + height) % height);
    }
    return m_desktops->grid().at(coords);
}

ToposOverrideMap ToposManager::builtinOverrides(const QString &name, QString *error) const
{
    const QString canonical = canonicalBuiltinName(name);
    ToposOverrideMap result;
    if (canonical == QLatin1String("Base Grid")) {
        return result;
    }
    if (canonical.isEmpty()) {
        if (error) *error = QStringLiteral("Unknown builtin: %1").arg(name);
        return result;
    }

    const QList<VirtualDesktop *> desktops = m_desktops->desktops();
    auto addCardinalWrap = [&](VirtualDesktop *source, ToposPort port, VirtualDesktopManager::Direction direction) {
        VirtualDesktop *plain = m_desktops->basisNeighbor(source, direction, false);
        VirtualDesktop *wrapped = m_desktops->basisNeighbor(source, direction, true);
        if (wrapped && wrapped != source && plain == source) {
            result.insert(ToposEndpoint{source->id(), port}, ToposArc{wrapped->id(), {}});
        }
    };

    if (canonical == QLatin1String("Torus") || canonical == QLatin1String("Cylinder X") || canonical == QLatin1String("Sphere")) {
        for (VirtualDesktop *desktop : desktops) {
            addCardinalWrap(desktop, ToposPort::East, VirtualDesktopManager::Direction::Right);
            addCardinalWrap(desktop, ToposPort::West, VirtualDesktopManager::Direction::Left);
        }
    }
    if (canonical == QLatin1String("Torus") || canonical == QLatin1String("Cylinder Y")) {
        for (VirtualDesktop *desktop : desktops) {
            addCardinalWrap(desktop, ToposPort::North, VirtualDesktopManager::Direction::Up);
            addCardinalWrap(desktop, ToposPort::South, VirtualDesktopManager::Direction::Down);
        }
    }

    if (canonical == QLatin1String("Sphere")) {
        const int width = m_desktops->grid().width();
        const int height = m_desktops->grid().height();
        for (VirtualDesktop *desktop : desktops) {
            const QPoint coords = m_desktops->grid().gridCoords(desktop);
            if (coords.y() == 0 && width > 0) {
                if (VirtualDesktop *target = m_desktops->grid().at(QPoint(width - 1 - coords.x(), 0))) {
                    result.insert(ToposEndpoint{desktop->id(), ToposPort::North}, ToposArc{target->id(), ToposTransport{4, false}});
                }
            }
            if (coords.y() == height - 1 && width > 0) {
                if (VirtualDesktop *target = m_desktops->grid().at(QPoint(width - 1 - coords.x(), height - 1))) {
                    result.insert(ToposEndpoint{desktop->id(), ToposPort::South}, ToposArc{target->id(), ToposTransport{4, false}});
                }
            }
            const struct DiagonalSpec { ToposPort port; int dx; int dy; } diagonals[] = {
                {ToposPort::NorthEast, 1, -1}, {ToposPort::NorthWest, -1, -1},
                {ToposPort::SouthEast, 1, 1}, {ToposPort::SouthWest, -1, 1},
            };
            for (const DiagonalSpec &spec : diagonals) {
                if ((spec.dy < 0 && coords.y() != 0) || (spec.dy > 0 && coords.y() != height - 1)) continue;
                int shiftedX = width > 0 ? (coords.x() + spec.dx + width) % width : coords.x();
                const int reflectedX = width - 1 - shiftedX;
                const int targetY = spec.dy < 0 ? 0 : height - 1;
                if (VirtualDesktop *target = m_desktops->grid().at(QPoint(reflectedX, targetY))) {
                    result.insert(ToposEndpoint{desktop->id(), spec.port}, ToposArc{target->id(), ToposTransport{4, false}});
                }
            }
        }
        return result;
    }

    const bool wrapX = canonical == QLatin1String("Torus") || canonical == QLatin1String("Cylinder X");
    const bool wrapY = canonical == QLatin1String("Torus") || canonical == QLatin1String("Cylinder Y");
    for (VirtualDesktop *desktop : desktops) {
        for (ToposPort port : {ToposPort::NorthEast, ToposPort::SouthEast, ToposPort::SouthWest, ToposPort::NorthWest}) {
            VirtualDesktop *plain = basisDiagonal(desktop, port, false, false);
            VirtualDesktop *wrapped = basisDiagonal(desktop, port, wrapX, wrapY);
            if (!plain && wrapped) {
                result.insert(ToposEndpoint{desktop->id(), port}, ToposArc{wrapped->id(), {}});
            }
        }
    }
    return result;
}

void ToposManager::updateDerivedState()
{
    QString match;
    for (const QString &builtin : listBuiltins()) {
        QString ignored;
        if (builtinOverrides(builtin, &ignored) == m_overrides) {
            match = builtin;
            break;
        }
    }
    if (match.isEmpty()) {
        for (auto it = m_profiles.cbegin(); it != m_profiles.cend(); ++it) {
            if (it->valid && it->compatible && it->overrides == m_overrides) {
                match = it.key();
                break;
            }
        }
    }
    const bool dirty = match.isEmpty();
    if (m_activeProfile != match || m_dirty != dirty) {
        m_activeProfile = match;
        m_dirty = dirty;
        Q_EMIT stateChanged();
    }
}

void ToposManager::loadSettings()
{
    QSettings settings(settingsPath(), QSettings::IniFormat);
    m_historyLimit = std::clamp(settings.value(QStringLiteral("General/HistoryLimit"), 50).toInt(), 1, 1000);
    m_persistHistory = settings.value(QStringLiteral("General/PersistHistory"), true).toBool();
    m_gestureDistance = std::clamp(settings.value(QStringLiteral("General/GestureDistance"), 200).toInt(), 50, 2000);
    m_settleThreshold = std::clamp(settings.value(QStringLiteral("General/SettleThreshold"), 0.25).toDouble(), 0.05, 0.95);
    m_showHandles = settings.value(QStringLiteral("General/ShowHandles"), true).toBool();
    m_showBridgePreview = settings.value(QStringLiteral("General/ShowBridgePreview"), true).toBool();
}

void ToposManager::saveSettings() const
{
    QSettings settings(settingsPath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("General/HistoryLimit"), m_historyLimit);
    settings.setValue(QStringLiteral("General/PersistHistory"), m_persistHistory);
    settings.setValue(QStringLiteral("General/GestureDistance"), m_gestureDistance);
    settings.setValue(QStringLiteral("General/SettleThreshold"), m_settleThreshold);
    settings.setValue(QStringLiteral("General/ShowHandles"), m_showHandles);
    settings.setValue(QStringLiteral("General/ShowBridgePreview"), m_showBridgePreview);
}

void ToposManager::saveHistory() const
{
    if (!m_persistHistory) return;
    QJsonObject root;
    root.insert(QStringLiteral("cursor"), m_historyCursor);
    QJsonArray entries;
    for (const HistoryEntry &historyEntry : m_history) {
        QJsonObject object{{QStringLiteral("label"), historyEntry.label}};
        QJsonArray overrides;
        for (auto it = historyEntry.overrides.cbegin(); it != historyEntry.overrides.cend(); ++it) {
            overrides.append(overrideJson(it.key(), it.value()));
        }
        object.insert(QStringLiteral("overrides"), overrides);
        entries.append(object);
    }
    root.insert(QStringLiteral("entries"), entries);
    QSaveFile file(historyPath());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
        file.commit();
    }
}

void ToposManager::importPersistentHistory()
{
    if (!m_persistHistory) return;
    QFile file(historyPath());
    if (!file.open(QIODevice::ReadOnly)) return;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) return;

    QSet<QString> desktopIds;
    for (VirtualDesktop *desktop : m_desktops->desktops()) desktopIds.insert(desktop->id());
    QVector<HistoryEntry> imported;
    const QJsonArray entries = document.object().value(QStringLiteral("entries")).toArray();
    for (const QJsonValue &value : entries) {
        if (!value.isObject()) continue;
        const QJsonObject object = value.toObject();
        ToposOverrideMap overrides;
        bool valid = true;
        for (const QJsonValue &overrideValue : object.value(QStringLiteral("overrides")).toArray()) {
            const QJsonObject o = overrideValue.toObject();
            const QString source = o.value(QStringLiteral("source")).toString();
            const auto port = parsePort(o.value(QStringLiteral("port")).toString());
            if (!desktopIds.contains(source) || !port) {
                valid = false;
                break;
            }
            const ToposEndpoint endpoint{source, *port};
            if (o.value(QStringLiteral("blocked")).toBool()) {
                overrides.insert(endpoint, std::nullopt);
            } else {
                const QString target = o.value(QStringLiteral("target")).toString();
                if (!desktopIds.contains(target)) {
                    valid = false;
                    break;
                }
                const QJsonObject t = o.value(QStringLiteral("transport")).toObject();
                overrides.insert(endpoint, ToposArc{target, ToposTransport{t.value(QStringLiteral("rotate")).toInt(), t.value(QStringLiteral("mirror")).toBool()}});
            }
        }
        if (valid) imported.append(HistoryEntry{object.value(QStringLiteral("label")).toString(), overrides});
    }
    if (!imported.isEmpty()) {
        m_history = imported;
        capHistory();
    }
}

void ToposManager::handleDesktopStructureChanged()
{
    if (!m_ready) return;
    m_traversals.clear();
    m_transitionHints.clear();
    cancelSelection();
    rescanProfiles();
    bumpRevision();
    updateDerivedState();
    Q_EMIT desktopSignatureChanged();
}

void ToposManager::handleDesktopRemoved()
{
    if (!m_ready) return;
    QSet<QString> ids;
    for (VirtualDesktop *desktop : m_desktops->desktops()) ids.insert(desktop->id());
    ToposOverrideMap cleaned;
    for (auto it = m_overrides.cbegin(); it != m_overrides.cend(); ++it) {
        if (!ids.contains(it.key().desktopId)) continue;
        if (it.value() && !ids.contains(it.value()->targetDesktopId)) continue;
        cleaned.insert(it.key(), it.value());
    }
    m_overrides = cleaned;
    clearHistory();
    handleDesktopStructureChanged();
}

void ToposManager::bumpRevision()
{
    ++m_revision;
    Q_EMIT revisionChanged();
    Q_EMIT stateChanged();
}

ToposPort ToposManager::graphPortForVector(const QPointF &vector, const ToposTransport &) const
{
    const qreal ax = std::abs(vector.x());
    const qreal ay = std::abs(vector.y());
    if (ax > 0.001 && ay / ax < s_diagonalAxisRatio) {
        return vector.x() >= 0 ? ToposPort::East : ToposPort::West;
    }
    if (ay > 0.001 && ax / ay < s_diagonalAxisRatio) {
        return vector.y() >= 0 ? ToposPort::South : ToposPort::North;
    }
    return quantizeDirection(vector);
}

void ToposManager::updateTraversal(const QPointF &rawDelta, LogicalOutput *output)
{
    if (!m_ready || !output) return;
    TraversalState &state = m_traversals[output];
    if (!state.active) {
        state = TraversalState{};
        state.active = true;
        state.origin = m_desktops->currentDesktop(output);
        state.cursor = state.origin;
        state.lastRawDelta = QPointF(0, 0);
    }
    if (!state.cursor) return;

    const QPointF rawIncrement = rawDelta - state.lastRawDelta;
    state.lastRawDelta = rawDelta;
    QPointF navigationIncrement(-rawIncrement.x() / m_gestureDistance,
                                -rawIncrement.y() / m_gestureDistance);
    navigationIncrement = applyTransport(navigationIncrement, state.frame);
    state.residual += navigationIncrement;

    for (int crossing = 0; crossing < s_maxCrossingsPerUpdate; ++crossing) {
        const qreal residualLength = length(state.residual);
        if (residualLength < 0.001) {
            state.activePort.reset();
            state.segmentProgress = 0;
            state.blocked = false;
            state.segmentTarget = nullptr;
            break;
        }

        const ToposPort candidate = graphPortForVector(state.residual, state.frame);
        if (!state.activePort) {
            state.activePort = candidate;
        } else if (*state.activePort != candidate) {
            const QPointF normalized = state.residual / residualLength;
            const qreal currentAlignment = dot(normalized, portVector(*state.activePort));
            if (currentAlignment < s_directionHysteresisAlignment || state.segmentProgress < 0.15) {
                state.activePort = candidate;
            }
        }

        const ToposPort port = *state.activePort;
        const QPointF direction = portGridVector(port);
        const qreal directionLengthSquared = dot(direction, direction);
        const qreal projection = std::max<qreal>(0, dot(state.residual, direction) / directionLengthSquared);
        state.segmentProgress = projection;

        if (!state.path.isEmpty()) {
            const ToposStep &last = state.path.constLast();
            const QPointF backwardsVector = applyTransport(-portVector(last.port), last.transport);
            const ToposPort backwardsPort = quantizeDirection(backwardsVector);
            if (port == backwardsPort && projection >= 1.0) {
                const ToposStep step = state.path.takeLast();
                state.residual -= direction;
                state.residual = applyTransport(state.residual, inverseTransport(step.transport));
                state.cursor = m_desktops->desktopForId(step.from);
                state.frame = {};
                for (const ToposStep &remaining : std::as_const(state.path)) {
                    state.frame = composeTransport(state.frame, remaining.transport);
                }
                state.activePort.reset();
                state.segmentProgress = 0;
                state.blocked = false;
                state.segmentTarget = nullptr;
                continue;
            }
        }

        const ToposResolvedArc arc = resolve(state.cursor, port, m_desktops->isNavigationWrappingAround());
        if (!arc.exists) {
            state.blocked = true;
            state.segmentTarget = nullptr;
            break;
        }
        state.blocked = false;
        state.segmentTarget = arc.target;
        if (projection < 1.0) {
            break;
        }

        state.path.append(ToposStep{state.cursor->id(), arc.target->id(), port, arc.transport});
        state.cursor = arc.target;
        state.residual -= direction;
        state.residual = applyTransport(state.residual, arc.transport);
        state.frame = composeTransport(state.frame, arc.transport);
        state.activePort.reset();
        state.segmentProgress = 0;
        state.segmentTarget = nullptr;
    }

    Q_EMIT traversalChanged(output);
}

ToposTraversalVisualState ToposManager::traversalVisualState(LogicalOutput *output) const
{
    const auto it = m_traversals.constFind(output);
    if (it == m_traversals.cend() || !it->active || !it->cursor) return {};
    ToposTraversalVisualState visual;
    visual.active = true;
    visual.blocked = it->blocked;
    visual.source = it->cursor;
    visual.target = it->segmentTarget;
    visual.port = it->activePort.value_or(ToposPort::East);
    if (it->blocked) {
        visual.progress = s_blockedMaximum * (1.0 - std::exp(-3.0 * it->segmentProgress));
    } else {
        visual.progress = std::clamp(it->segmentProgress, 0.0, 1.0);
    }

    if (it->blocked && it->activePort) {
        visual.offset = portGridVector(*it->activePort) * visual.progress;
    } else {
        visual.offset = it->residual;
    }

    // Paint the current desktop and every directly reachable neighbor at once.
    // This makes the gesture a continuous 2-D surface instead of snapping
    // between one source/target pair at a time.
    visual.placements.append(ToposTraversalPlacement{it->cursor, QPointF(0, 0)});
    for (int p = 0; p < 8; ++p) {
        const ToposPort port = static_cast<ToposPort>(p);
        const ToposResolvedArc arc = resolve(it->cursor, port, m_desktops->isNavigationWrappingAround());
        if (!arc.exists || !arc.target || arc.target == it->cursor) {
            continue;
        }
        visual.placements.append(ToposTraversalPlacement{arc.target, portGridVector(port)});
    }
    return visual;
}

VirtualDesktop *ToposManager::finishTraversal(LogicalOutput *output)
{
    auto it = m_traversals.find(output);
    if (it == m_traversals.end() || !it->active || !it->cursor) {
        return m_desktops->currentDesktop(output);
    }
    TraversalState state = it.value();
    const ToposTraversalVisualState visual = traversalVisualState(output);
    VirtualDesktop *finalDesktop = state.cursor;
    ToposTransitionHint hint;

    if (state.activePort) {
        hint.valid = true;
        hint.from = state.cursor;
        hint.to = state.segmentTarget;
        hint.port = *state.activePort;
        hint.startProgress = visual.progress;
        hint.startOffset = visual.offset;
        hint.placements = visual.placements;
        if (!state.blocked && state.segmentTarget && state.segmentProgress >= m_settleThreshold) {
            finalDesktop = state.segmentTarget;
            hint.endProgress = 1.0;
            hint.endOffset = portGridVector(*state.activePort);
        } else {
            hint.endProgress = 0.0;
            hint.endOffset = QPointF();
        }
        m_transitionHints.insert(output, hint);
    }

    m_traversals.erase(it);
    return finalDesktop;
}

void ToposManager::cancelTraversal(LogicalOutput *output)
{
    if (m_traversals.remove(output)) {
        m_transitionHints.remove(output);
        Q_EMIT traversalCancelled(output);
    }
}

void ToposManager::armTransition(VirtualDesktop *from, ToposPort port, LogicalOutput *output)
{
    if (!from) return;
    const ToposResolvedArc arc = resolve(from, port, m_desktops->isNavigationWrappingAround());
    if (!arc.exists || !arc.custom || !arc.target || arc.target == from) return;
    m_transitionHints.insert(output, ToposTransitionHint{true, from, arc.target, port, 0.0, 1.0});
}

std::optional<ToposTransitionHint> ToposManager::takeTransitionHint(LogicalOutput *output)
{
    auto it = m_transitionHints.find(output);
    if (it == m_transitionHints.end()) return std::nullopt;
    const ToposTransitionHint hint = it.value();
    m_transitionHints.erase(it);
    return hint;
}

} // namespace KWin
