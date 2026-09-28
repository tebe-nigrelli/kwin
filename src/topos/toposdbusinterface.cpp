/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "toposdbusinterface.h"

#include "toposmanager.h"
#include "toposadaptor.h"
#include "virtualdesktops.h"

#include <QDBusConnection>

namespace KWin
{

ToposDBusInterface::ToposDBusInterface(ToposManager *manager)
    : QObject(manager)
    , m_manager(manager)
{
    new ToposAdaptor(this);
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/Topos"),
                                                 QStringLiteral("org.kde.KWin.Topos"),
                                                 this);

    connect(manager, &ToposManager::stateChanged, this, [this]() {
        Q_EMIT StateChanged();
        Q_EMIT stateChanged();
    });
    connect(manager, &ToposManager::revisionChanged, this, [this]() {
        Q_EMIT StateChanged();
        Q_EMIT stateChanged();
    });
    connect(manager, &ToposManager::profilesChanged, this, &ToposDBusInterface::ProfilesChanged);
    connect(manager, &ToposManager::historyChanged, this, [this]() {
        Q_EMIT HistoryChanged();
        Q_EMIT historyChanged();
    });
    connect(manager, &ToposManager::settingsChanged, this, [this]() {
        Q_EMIT StateChanged();
        Q_EMIT stateChanged();
    });
    connect(manager, &ToposManager::desktopSignatureChanged, this, [this]() {
        Q_EMIT DesktopSignatureChanged();
        Q_EMIT desktopSignatureChanged();
    });
}

ToposDBusInterface::~ToposDBusInterface()
{
    QDBusConnection::sessionBus().unregisterObject(QStringLiteral("/Topos"));
}

int ToposDBusInterface::apiVersion() const { return ToposApiVersion; }
bool ToposDBusInterface::ready() const { return m_manager->isReady(); }
qulonglong ToposDBusInterface::revision() const { return m_manager->revision(); }
QString ToposDBusInterface::activeProfile() const { return m_manager->activeProfile(); }
QString ToposDBusInterface::lastLoadedProfile() const { return m_manager->lastLoadedProfile(); }
bool ToposDBusInterface::dirty() const { return m_manager->isDirty(); }
bool ToposDBusInterface::canUndo() const { return m_manager->canUndo(); }
bool ToposDBusInterface::canRedo() const { return m_manager->canRedo(); }
int ToposDBusInterface::historyLimit() const { return m_manager->historyLimit(); }
void ToposDBusInterface::setHistoryLimit(int limit) { m_manager->setHistoryLimit(limit); }
bool ToposDBusInterface::persistHistory() const { return m_manager->persistHistory(); }
void ToposDBusInterface::setPersistHistory(bool enabled) { m_manager->setPersistHistory(enabled); }
int ToposDBusInterface::gestureDistance() const { return m_manager->gestureDistance(); }
void ToposDBusInterface::setGestureDistance(int distance) { m_manager->setGestureDistance(distance); }
double ToposDBusInterface::settleThreshold() const { return m_manager->settleThreshold(); }
void ToposDBusInterface::setSettleThreshold(double threshold) { m_manager->setSettleThreshold(threshold); }
bool ToposDBusInterface::showHandles() const { return m_manager->showHandles(); }
void ToposDBusInterface::setShowHandles(bool show) { m_manager->setShowHandles(show); }
bool ToposDBusInterface::showBridgePreview() const { return m_manager->showBridgePreview(); }
void ToposDBusInterface::setShowBridgePreview(bool show) { m_manager->setShowBridgePreview(show); }
QString ToposDBusInterface::topologyGraphLayout() const { return m_manager->topologyGraphLayout(); }
void ToposDBusInterface::setTopologyGraphLayout(const QString &layout) { m_manager->setTopologyGraphLayout(layout); }
double ToposDBusInterface::topologyGraphSpread() const { return m_manager->topologyGraphSpread(); }
void ToposDBusInterface::setTopologyGraphSpread(double spread) { m_manager->setTopologyGraphSpread(spread); }

QStringList ToposDBusInterface::desktopNames() const
{
    QStringList names;
    for (VirtualDesktop *desktop : VirtualDesktopManager::self()->desktops()) {
        names << desktop->name();
    }
    return names;
}

bool ToposDBusInterface::report(bool ok, const QString &error)
{
    if (!ok && calledFromDBus()) {
        sendErrorReply(QStringLiteral("org.kde.KWin.Topos.Error"), error);
    }
    return ok;
}

bool ToposDBusInterface::Reset()
{
    QString error;
    return report(m_manager->reset(&error), error);
}

bool ToposDBusInterface::ApplyBuiltin(const QString &name)
{
    QString error;
    return report(m_manager->applyBuiltin(name, &error), error);
}

QStringList ToposDBusInterface::ListBuiltins() const { return m_manager->listBuiltins(); }
QStringList ToposDBusInterface::ListProfiles() const { return m_manager->listProfiles(); }
QStringList ToposDBusInterface::ListProfilesAll() const { return m_manager->listAllProfiles(); }

bool ToposDBusInterface::LoadProfile(const QString &name)
{
    QString error;
    return report(m_manager->loadProfile(name, &error), error);
}

bool ToposDBusInterface::SaveProfile(const QString &name, bool overwrite)
{
    QString error;
    return report(m_manager->saveProfile(name, overwrite, &error), error);
}

bool ToposDBusInterface::RenameProfile(const QString &oldName, const QString &newName, bool overwrite)
{
    QString error;
    return report(m_manager->renameProfile(oldName, newName, overwrite, &error), error);
}

bool ToposDBusInterface::DeleteProfile(const QString &name)
{
    QString error;
    return report(m_manager->deleteProfile(name, &error), error);
}

bool ToposDBusInterface::SetArc(const QString &source, const QString &portString, const QString &target, bool bidirectional, int rotationSteps, bool mirrored)
{
    const auto port = parsePort(portString);
    if (!port) {
        return report(false, QStringLiteral("Unknown port: %1").arg(portString));
    }
    QString error;
    return report(m_manager->setArc(source, *port, target, bidirectional, ToposTransport{rotationSteps, mirrored}, &error), error);
}

bool ToposDBusInterface::BlockArc(const QString &source, const QString &portString)
{
    const auto port = parsePort(portString);
    if (!port) return report(false, QStringLiteral("Unknown port: %1").arg(portString));
    QString error;
    return report(m_manager->blockArc(source, *port, &error), error);
}

bool ToposDBusInterface::RestoreArc(const QString &source, const QString &portString)
{
    const auto port = parsePort(portString);
    if (!port) return report(false, QStringLiteral("Unknown port: %1").arg(portString));
    QString error;
    return report(m_manager->restoreArc(source, *port, &error), error);
}

bool ToposDBusInterface::CollapseVertex(const QString &source, const QString &destination)
{
    QString error;
    return report(m_manager->collapseVertex(source, destination, &error), error);
}

bool ToposDBusInterface::Undo(int count) { return m_manager->undo(count); }
bool ToposDBusInterface::Redo(int count) { return m_manager->redo(count); }
void ToposDBusInterface::ClearHistory() { m_manager->clearHistory(); }
bool ToposDBusInterface::GotoHistory(int index) { return m_manager->gotoHistory(index); }
QString ToposDBusInterface::GetState() const { return m_manager->stateJson(); }
QString ToposDBusInterface::GetGraph() const { return m_manager->graphJson(); }
QString ToposDBusInterface::GetHistory() const { return m_manager->historyJson(); }

} // namespace KWin

#include "moc_toposdbusinterface.cpp"
