/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "topostypes.h"

#include <kwin_export.h>

#include <QObject>
#include <QPointF>
#include <QVariantMap>
#include <QVector>

#include <memory>
#include <functional>
#include <optional>

class QFileSystemWatcher;

namespace KWin
{

class LogicalOutput;
class VirtualDesktop;
class VirtualDesktopManager;
class ToposDBusInterface;

struct ToposResolvedArc
{
    bool exists = false;
    bool custom = false;
    VirtualDesktop *target = nullptr;
    ToposTransport transport;
};

struct ToposStep
{
    QString from;
    QString to;
    ToposPort port = ToposPort::East;
    ToposTransport transport;
};

struct ToposTraversalPlacement
{
    VirtualDesktop *desktop = nullptr;
    QPointF position;
};

struct ToposTraversalVisualState
{
    bool active = false;
    bool blocked = false;
    VirtualDesktop *source = nullptr;
    VirtualDesktop *target = nullptr;
    ToposPort port = ToposPort::East;
    qreal progress = 0;
    QPointF offset;
    QVector<ToposTraversalPlacement> placements;
};

struct ToposTransitionHint
{
    bool valid = false;
    VirtualDesktop *from = nullptr;
    VirtualDesktop *to = nullptr;
    ToposPort port = ToposPort::East;
    qreal startProgress = 0;
    qreal endProgress = 1;
    QPointF startOffset;
    QPointF endOffset;
    QVector<ToposTraversalPlacement> placements;
};

class KWIN_EXPORT ToposManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged)
    Q_PROPERTY(qulonglong revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY stateChanged)
    Q_PROPERTY(bool dirty READ isDirty NOTIFY stateChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(int historyLimit READ historyLimit WRITE setHistoryLimit NOTIFY settingsChanged)
    Q_PROPERTY(bool persistHistory READ persistHistory WRITE setPersistHistory NOTIFY settingsChanged)
    Q_PROPERTY(int gestureDistance READ gestureDistance WRITE setGestureDistance NOTIFY settingsChanged)
    Q_PROPERTY(qreal settleThreshold READ settleThreshold WRITE setSettleThreshold NOTIFY settingsChanged)
    Q_PROPERTY(bool showHandles READ showHandles WRITE setShowHandles NOTIFY settingsChanged)
    Q_PROPERTY(bool showBridgePreview READ showBridgePreview WRITE setShowBridgePreview NOTIFY settingsChanged)
    Q_PROPERTY(QString topologyGraphLayout READ topologyGraphLayout WRITE setTopologyGraphLayout NOTIFY settingsChanged)
    Q_PROPERTY(qreal topologyGraphSpread READ topologyGraphSpread WRITE setTopologyGraphSpread NOTIFY settingsChanged)
    Q_PROPERTY(QString selectedDesktop READ selectedDesktop NOTIFY selectionChanged)
    Q_PROPERTY(int selectedPort READ selectedPort NOTIFY selectionChanged)

public:
    explicit ToposManager(VirtualDesktopManager *desktops);
    ~ToposManager() override;

    void initialize();
    bool isReady() const;
    qulonglong revision() const;

    VirtualDesktop *neighbor(VirtualDesktop *desktop, ToposPort port, bool wrap) const;
    ToposResolvedArc resolve(VirtualDesktop *desktop, ToposPort port, bool wrap) const;
    ToposOverrideMap overrides() const;

    QString activeProfile() const;
    QString lastLoadedProfile() const;
    bool isDirty() const;
    QStringList listBuiltins() const;
    QStringList listProfiles() const;
    QStringList listAllProfiles() const;

    bool reset(QString *error = nullptr);
    bool applyBuiltin(const QString &name, QString *error = nullptr);
    bool loadProfile(const QString &name, QString *error = nullptr);
    bool saveProfile(const QString &name, bool overwrite, QString *error = nullptr);
    bool renameProfile(const QString &oldName, const QString &newName, bool overwrite, QString *error = nullptr);
    bool deleteProfile(const QString &name, QString *error = nullptr);

    bool setArc(const QString &sourceSelector, ToposPort port, const QString &targetSelector,
                bool bidirectional, ToposTransport transport = {}, QString *error = nullptr);
    bool blockArc(const QString &sourceSelector, ToposPort port, QString *error = nullptr);
    bool restoreArc(const QString &sourceSelector, ToposPort port, QString *error = nullptr);
    bool collapseVertex(const QString &victimSelector, const QString &representativeSelector, QString *error = nullptr);

    bool undo(int count = 1);
    bool redo(int count = 1);
    void clearHistory();
    bool gotoHistory(int index);
    bool canUndo() const;
    bool canRedo() const;
    int historyLimit() const;
    void setHistoryLimit(int limit);

    bool persistHistory() const;
    void setPersistHistory(bool enabled);
    int gestureDistance() const;
    void setGestureDistance(int distance);
    qreal settleThreshold() const;
    void setSettleThreshold(qreal threshold);
    bool showHandles() const;
    void setShowHandles(bool show);
    bool showBridgePreview() const;
    void setShowBridgePreview(bool show);
    QString topologyGraphLayout() const;
    void setTopologyGraphLayout(const QString &layout);
    qreal topologyGraphSpread() const;
    void setTopologyGraphSpread(qreal spread);

    QString stateJson() const;
    QString graphJson() const;
    QString historyJson() const;

    VirtualDesktop *resolveDesktopSelector(const QString &selector, QString *error = nullptr) const;

    Q_INVOKABLE QVariantMap edgeInfo(const QString &desktopId, int port) const;
    Q_INVOKABLE void selectPort(const QString &desktopId, int port);
    Q_INVOKABLE void blockSelectedPort();
    Q_INVOKABLE void linkSelectedTo(const QString &desktopId, bool bidirectional);
    Q_INVOKABLE void unlinkPort(const QString &desktopId, int port);
    Q_INVOKABLE void restorePort(const QString &desktopId, int port);
    Q_INVOKABLE void cancelSelection();
    Q_INVOKABLE QStringList compatibleProfiles() const;
    Q_INVOKABLE QStringList presetNames() const;
    Q_INVOKABLE QString applyPreset(const QString &name);
    Q_INVOKABLE QString storePreset(const QString &name);
    Q_INVOKABLE QString removePreset(const QString &name);

    QString selectedDesktop() const;
    int selectedPort() const;

    void updateTraversal(const QPointF &rawDelta, LogicalOutput *output);
    VirtualDesktop *finishTraversal(LogicalOutput *output);
    void cancelTraversal(LogicalOutput *output);
    ToposTraversalVisualState traversalVisualState(LogicalOutput *output) const;

    void armTransition(VirtualDesktop *from, ToposPort port, LogicalOutput *output = nullptr);
    std::optional<ToposTransitionHint> takeTransitionHint(LogicalOutput *output);

Q_SIGNALS:
    void readyChanged();
    void revisionChanged();
    void stateChanged();
    void profilesChanged();
    void historyChanged();
    void desktopSignatureChanged();
    void settingsChanged();
    void selectionChanged();
    void traversalChanged(KWin::LogicalOutput *output);
    void traversalCancelled(KWin::LogicalOutput *output);

private:
    struct HistoryEntry {
        QString label;
        ToposOverrideMap overrides;
    };

    struct ProfileEntry {
        QString name;
        QString path;
        QStringList signature;
        ToposOverrideMap overrides;
        bool valid = false;
        bool compatible = false;
        QString error;
    };

    struct TraversalState {
        bool active = false;
        VirtualDesktop *origin = nullptr;
        VirtualDesktop *cursor = nullptr;
        QVector<ToposStep> path;
        QPointF lastRawDelta;
        QPointF residual;
        ToposTransport frame;
        std::optional<ToposPort> activePort;
        qreal segmentProgress = 0;
        bool blocked = false;
        VirtualDesktop *segmentTarget = nullptr;
    };

    bool mutate(const QString &label, const std::function<bool(QString *)> &operation, QString *error);
    void setOverrides(const ToposOverrideMap &overrides, bool bumpRevision = true);
    void pushHistory(const QString &label);
    void applyHistoryEntry(int index);
    void capHistory();
    void saveHistory() const;
    void importPersistentHistory();

    void rescanProfiles();
    ProfileEntry parseProfile(const QString &path) const;
    bool writeProfile(const QString &path, QString *error) const;
    QString profileDirectory() const;
    QString settingsPath() const;
    QString historyPath() const;
    bool validProfileName(const QString &name, QString *error) const;
    bool signaturesCompatible(const QStringList &a, const QStringList &b) const;
    QStringList currentSignature() const;
    QHash<QString, VirtualDesktop *> aliasMapping(const QStringList &aliases, const QStringList &names, QString *error) const;

    ToposOverrideMap builtinOverrides(const QString &name, QString *error = nullptr) const;
    VirtualDesktop *basisDiagonal(VirtualDesktop *desktop, ToposPort port, bool wrapX, bool wrapY) const;
    ToposPort graphPortForVector(const QPointF &vector, const ToposTransport &frame) const;
    void updateDerivedState();
    void loadSettings();
    void saveSettings() const;
    void handleDesktopStructureChanged();
    void handleDesktopRemoved();
    void bumpRevision();

    VirtualDesktopManager *m_desktops;
    bool m_ready = false;
    qulonglong m_revision = 0;
    ToposOverrideMap m_overrides;

    QHash<QString, ProfileEntry> m_profiles;
    std::unique_ptr<QFileSystemWatcher> m_profileWatcher;
    std::unique_ptr<ToposDBusInterface> m_dbus;

    QVector<HistoryEntry> m_history;
    int m_historyCursor = -1;
    int m_historyLimit = 50;
    bool m_persistHistory = true;
    int m_gestureDistance = 200;
    qreal m_settleThreshold = 0.25;
    bool m_showHandles = true;
    bool m_showBridgePreview = true;
    QString m_topologyGraphLayout = QStringLiteral("grid");
    qreal m_topologyGraphSpread = 1.35;

    QString m_activeProfile;
    QString m_lastLoadedProfile;
    bool m_dirty = false;

    QString m_selectedDesktop;
    int m_selectedPort = -1;

    QHash<LogicalOutput *, TraversalState> m_traversals;
    QHash<LogicalOutput *, ToposTransitionHint> m_transitionHints;
};

} // namespace KWin
