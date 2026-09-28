/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QDBusContext>
#include <QObject>
#include <QStringList>

namespace KWin
{

class ToposManager;

class ToposDBusInterface : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KWin.Topos")
    Q_PROPERTY(int apiVersion READ apiVersion CONSTANT)
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(qulonglong revision READ revision NOTIFY stateChanged)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY stateChanged)
    Q_PROPERTY(QString lastLoadedProfile READ lastLoadedProfile NOTIFY stateChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY stateChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(int historyLimit READ historyLimit WRITE setHistoryLimit NOTIFY stateChanged)
    Q_PROPERTY(bool persistHistory READ persistHistory WRITE setPersistHistory NOTIFY stateChanged)
    Q_PROPERTY(int gestureDistance READ gestureDistance WRITE setGestureDistance NOTIFY stateChanged)
    Q_PROPERTY(double settleThreshold READ settleThreshold WRITE setSettleThreshold NOTIFY stateChanged)
    Q_PROPERTY(bool showHandles READ showHandles WRITE setShowHandles NOTIFY stateChanged)
    Q_PROPERTY(bool showBridgePreview READ showBridgePreview WRITE setShowBridgePreview NOTIFY stateChanged)
    Q_PROPERTY(QStringList desktopNames READ desktopNames NOTIFY desktopSignatureChanged)

public:
    explicit ToposDBusInterface(ToposManager *manager);
    ~ToposDBusInterface() override;

    int apiVersion() const;
    bool ready() const;
    qulonglong revision() const;
    QString activeProfile() const;
    QString lastLoadedProfile() const;
    bool dirty() const;
    bool canUndo() const;
    bool canRedo() const;
    int historyLimit() const;
    void setHistoryLimit(int limit);
    bool persistHistory() const;
    void setPersistHistory(bool enabled);
    int gestureDistance() const;
    void setGestureDistance(int distance);
    double settleThreshold() const;
    void setSettleThreshold(double threshold);
    bool showHandles() const;
    void setShowHandles(bool show);
    bool showBridgePreview() const;
    void setShowBridgePreview(bool show);
    QStringList desktopNames() const;

public Q_SLOTS:
    bool Reset();
    bool ApplyBuiltin(const QString &name);
    QStringList ListBuiltins() const;
    QStringList ListProfiles() const;
    QStringList ListProfilesAll() const;
    bool LoadProfile(const QString &name);
    bool SaveProfile(const QString &name, bool overwrite);
    bool RenameProfile(const QString &oldName, const QString &newName, bool overwrite);
    bool DeleteProfile(const QString &name);

    bool SetArc(const QString &source, const QString &port, const QString &target, bool bidirectional, int rotationSteps, bool mirrored);
    bool BlockArc(const QString &source, const QString &port);
    bool RestoreArc(const QString &source, const QString &port);
    bool CollapseVertex(const QString &source, const QString &destination);

    bool Undo(int count);
    bool Redo(int count);
    void ClearHistory();
    bool GotoHistory(int index);

    QString GetState() const;
    QString GetGraph() const;
    QString GetHistory() const;

Q_SIGNALS:
    void StateChanged();
    void ProfilesChanged();
    void HistoryChanged();
    void DesktopSignatureChanged();
    void stateChanged();
    void historyChanged();
    void desktopSignatureChanged();

private:
    bool report(bool ok, const QString &error);
    ToposManager *m_manager;
};

} // namespace KWin
