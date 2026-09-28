/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

namespace
{
constexpr auto service = "org.kde.KWin";
constexpr auto path = "/Topos";
constexpr auto interfaceName = "org.kde.KWin.Topos";

QDBusMessage call(QDBusInterface &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage message = iface.callWithArgumentList(QDBus::Block, method, args);
    if (message.type() == QDBusMessage::ErrorMessage) {
        QTextStream(stderr) << "toposctl: " << message.errorMessage() << '\n';
    }
    return message;
}

bool ok(const QDBusMessage &message)
{
    if (message.type() == QDBusMessage::ErrorMessage) return false;
    if (message.arguments().isEmpty()) return true;
    return message.arguments().constFirst().toBool();
}

void printStringList(const QStringList &values, bool quiet)
{
    if (quiet) return;
    QTextStream out(stdout);
    for (const QString &value : values) out << value << '\n';
}

void printJsonOrPretty(const QString &json, bool compact)
{
    QTextStream out(stdout);
    if (compact) {
        out << json << '\n';
        return;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8(), &error);
    if (error.error == QJsonParseError::NoError) {
        out << document.toJson(QJsonDocument::Indented);
    } else {
        out << json << '\n';
    }
}

int usage(QCommandLineParser &parser, const QString &message = {})
{
    if (!message.isEmpty()) QTextStream(stderr) << "toposctl: " << message << '\n';
    parser.showHelp(message.isEmpty() ? 0 : 2);
    return 2;
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("toposctl"));
    QCoreApplication::setApplicationVersion(QStringLiteral("1"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Control Topos virtual-desktop routing in KWin"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption({QStringLiteral("json"), QStringLiteral("Emit compact JSON where applicable")});
    parser.addOption({QStringLiteral("quiet"), QStringLiteral("Suppress normal output")});
    parser.addOption({QStringLiteral("overwrite"), QStringLiteral("Replace an existing user profile")});
    parser.addOption({QStringLiteral("bidirectional"), QStringLiteral("Create the inverse arc too")});
    parser.addOption({QStringLiteral("rotate"), QStringLiteral("Transport rotation in 45-degree steps"), QStringLiteral("steps"), QStringLiteral("0")});
    parser.addOption({QStringLiteral("mirror"), QStringLiteral("Mirror orientation transport")});
    parser.addOption({QStringLiteral("all"), QStringLiteral("Include incompatible/invalid profiles")});
    parser.addPositionalArgument(QStringLiteral("command"), QStringLiteral("status, reset, preset, config, edge, vertex, undo, redo, history"));
    parser.addPositionalArgument(QStringLiteral("args"), QStringLiteral("Command arguments"), QStringLiteral("[args...]"));
    parser.process(app);

    const QStringList positional = parser.positionalArguments();
    if (positional.isEmpty()) return usage(parser);

    QDBusInterface iface(QString::fromLatin1(service), QString::fromLatin1(path), QString::fromLatin1(interfaceName), QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        QTextStream(stderr) << "toposctl: Topos is not running (org.kde.KWin.Topos unavailable)\n";
        return 1;
    }

    const bool json = parser.isSet(QStringLiteral("json"));
    const bool quiet = parser.isSet(QStringLiteral("quiet"));
    const QString command = positional[0].toLower();
    const QStringList args = positional.mid(1);

    if (command == QLatin1String("status")) {
        const QDBusMessage reply = call(iface, QStringLiteral("GetState"));
        if (reply.type() == QDBusMessage::ErrorMessage) return 1;
        if (!quiet) printJsonOrPretty(reply.arguments().value(0).toString(), json);
        return 0;
    }
    if (command == QLatin1String("reset")) {
        return ok(call(iface, QStringLiteral("Reset"))) ? 0 : 1;
    }
    if (command == QLatin1String("preset")) {
        if (args.value(0) == QLatin1String("list")) {
            const auto reply = call(iface, QStringLiteral("ListBuiltins"));
            if (reply.type() == QDBusMessage::ErrorMessage) return 1;
            printStringList(reply.arguments().value(0).toStringList(), quiet);
            return 0;
        }
        if (args.value(0) == QLatin1String("apply") && args.size() >= 2) {
            return ok(call(iface, QStringLiteral("ApplyBuiltin"), {args.mid(1).join(QLatin1Char(' '))})) ? 0 : 1;
        }
        return usage(parser, QStringLiteral("preset expects 'list' or 'apply NAME'"));
    }
    if (command == QLatin1String("config")) {
        const QString sub = args.value(0).toLower();
        if (sub == QLatin1String("list")) {
            const QString method = parser.isSet(QStringLiteral("all")) ? QStringLiteral("ListProfilesAll") : QStringLiteral("ListProfiles");
            const auto reply = call(iface, method);
            if (reply.type() == QDBusMessage::ErrorMessage) return 1;
            printStringList(reply.arguments().value(0).toStringList(), quiet);
            return 0;
        }
        if (sub == QLatin1String("load") && args.size() >= 2) return ok(call(iface, QStringLiteral("LoadProfile"), {args.mid(1).join(QLatin1Char(' '))})) ? 0 : 1;
        if (sub == QLatin1String("save") && args.size() >= 2) return ok(call(iface, QStringLiteral("SaveProfile"), {args.mid(1).join(QLatin1Char(' ')), parser.isSet(QStringLiteral("overwrite"))})) ? 0 : 1;
        if (sub == QLatin1String("rename") && args.size() == 3) return ok(call(iface, QStringLiteral("RenameProfile"), {args[1], args[2], parser.isSet(QStringLiteral("overwrite"))})) ? 0 : 1;
        if (sub == QLatin1String("delete") && args.size() >= 2) return ok(call(iface, QStringLiteral("DeleteProfile"), {args.mid(1).join(QLatin1Char(' '))})) ? 0 : 1;
        return usage(parser, QStringLiteral("config expects list/load/save/rename/delete"));
    }
    if (command == QLatin1String("edge")) {
        const QString sub = args.value(0).toLower();
        if (sub == QLatin1String("list")) {
            const auto reply = call(iface, QStringLiteral("GetGraph"));
            if (reply.type() == QDBusMessage::ErrorMessage) return 1;
            if (!quiet) printJsonOrPretty(reply.arguments().value(0).toString(), json);
            return 0;
        }
        if (sub == QLatin1String("set") && args.size() == 4) {
            bool rotateOk = false;
            const int rotate = parser.value(QStringLiteral("rotate")).toInt(&rotateOk);
            if (!rotateOk) return usage(parser, QStringLiteral("--rotate must be an integer"));
            return ok(call(iface, QStringLiteral("SetArc"), {args[1], args[2], args[3], parser.isSet(QStringLiteral("bidirectional")), rotate, parser.isSet(QStringLiteral("mirror"))})) ? 0 : 1;
        }
        if (sub == QLatin1String("block") && args.size() == 3) return ok(call(iface, QStringLiteral("BlockArc"), {args[1], args[2]})) ? 0 : 1;
        if (sub == QLatin1String("restore") && args.size() == 3) return ok(call(iface, QStringLiteral("RestoreArc"), {args[1], args[2]})) ? 0 : 1;
        return usage(parser, QStringLiteral("edge expects list/set/block/restore"));
    }
    if (command == QLatin1String("vertex") && args.value(0) == QLatin1String("collapse") && args.size() == 3) {
        return ok(call(iface, QStringLiteral("CollapseVertex"), {args[1], args[2]})) ? 0 : 1;
    }
    if (command == QLatin1String("undo") || command == QLatin1String("redo")) {
        bool countOk = true;
        const int count = args.isEmpty() ? 1 : args[0].toInt(&countOk);
        if (!countOk || count < 1) return usage(parser, QStringLiteral("undo/redo count must be positive"));
        return ok(call(iface, command == QLatin1String("undo") ? QStringLiteral("Undo") : QStringLiteral("Redo"), {count})) ? 0 : 1;
    }
    if (command == QLatin1String("history")) {
        const QString sub = args.value(0).toLower();
        if (sub == QLatin1String("list")) {
            const auto reply = call(iface, QStringLiteral("GetHistory"));
            if (reply.type() == QDBusMessage::ErrorMessage) return 1;
            if (!quiet) printJsonOrPretty(reply.arguments().value(0).toString(), json);
            return 0;
        }
        if (sub == QLatin1String("clear")) return call(iface, QStringLiteral("ClearHistory")).type() == QDBusMessage::ErrorMessage ? 1 : 0;
        if (sub == QLatin1String("goto") && args.size() == 2) {
            bool indexOk = false;
            const int index = args[1].toInt(&indexOk);
            if (!indexOk) return usage(parser, QStringLiteral("history index must be an integer"));
            return ok(call(iface, QStringLiteral("GotoHistory"), {index})) ? 0 : 1;
        }
        return usage(parser, QStringLiteral("history expects list/clear/goto"));
    }

    return usage(parser, QStringLiteral("unknown command: %1").arg(command));
}
