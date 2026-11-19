// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/format.js" as Format
import "../code/limits.js" as Limits
import "../code/style.js" as Style
import ".."

PlasmaComponents.ScrollView {
    id: pool
    objectName: "usagePool"

    required property var entry
    required property var innerLimit
    required property Words texts
    required property real nowMs
    required property bool showCredits

    readonly property real edge: Style.contentEdge(Kirigami.Units.largeSpacing)
    readonly property var accounts: Array.from(entry?.accounts ?? [])
    readonly property var periodOrder: ({ session: 0, week: 1, month: 2 })
    readonly property var otherPeriods: {
        const periods = Array.from(entry?.otherPeriods ?? []);
        for (const window of [entry?.session, entry?.week]) {
            if ((window?.accountAverage === true || window?.period === "session" && accounts.length > 1)
                && window.period !== entry?.weekly?.period
                && !periods.some(other => other.period === window.period)) {
                periods.push(window);
            }
        }
        return periods.sort((a, b) => periodRank(a) - periodRank(b));
    }
    readonly property bool stale: entry?.lastError !== undefined || Limits.allStale(entry)

    Layout.fillWidth: true
    Layout.minimumHeight: 0
    Layout.preferredWidth: 0
    contentWidth: availableWidth
    contentHeight: snapshot.implicitHeight
    T.ScrollBar.horizontal.policy: T.ScrollBar.AlwaysOff

    function periodRank(window) {
        return periodOrder[window.period] ?? 3;
    }

    function periodLabel(window) {
        switch (window.period) {
        case "week":
            return i18nc("@label a quota window", "Weekly");
        case "month":
            return i18nc("@label a quota window", "Monthly");
        case "session":
            return window.windowSeconds === 5 * 3600 ? i18nc("@label a quota window", "%1-hour session", Format.whole(5))
                                                     : i18nc("@label a quota window", "Session");
        default:
            return i18nc("@label a quota window", "Other period");
        }
    }

    function accountRows(account) {
        const rows = [];
        if ((account.session || account.sessionUnknown === true) && account.weekly?.period !== "session") {
            const session = account.session ?? { period: "session", windowSeconds: 5 * 3600 };
            rows.push({ label: periodLabel(session), window: session });
        }
        if (account.weekly) {
            rows.push({ label: i18nc("@label:group a period and its scope", "%1 · All models", periodLabel(account.weekly)),
                        window: account.weekly });
        }
        if (account.week) {
            rows.push({ label: periodLabel(account.week), window: account.week });
        }
        for (const other of account.otherPeriods ?? []) {
            rows.push({ label: periodLabel(other), window: other });
        }
        rows.sort((a, b) => periodRank(a.window) - periodRank(b.window));
        for (const scoped of account.scoped ?? []) {
            rows.push({ label: i18nc("@label:group a period and a model", "%1 · %2", periodLabel(scoped), scoped.label), window: scoped });
        }
        return rows;
    }

    component Detail: Text {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        color: Style.dim(Kirigami.Theme.textColor)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
    }

    component LimitRow: ColumnLayout {
        id: row
        objectName: "poolLimit"

        required property string label
        required property var window
        required property real reset
        property bool stale: false
        property string resetCaption: ""

        readonly property string resetText: pool.texts.countdown(reset, pool.nowMs)
        readonly property string usageText: pool.texts.percentText(window.percent)
        readonly property color barColor: stale ? Style.dim(Kirigami.Theme.textColor)
                                                : Style.levelColor(Format.level(window.percent), Kirigami.Theme)

        Accessible.role: Number.isFinite(window.percent) ? Accessible.ProgressBar : Accessible.StaticText
        Accessible.name: label
        Accessible.description: !resetText ? usageText : resetCaption
            ? i18nc("@info:accessible usage and a pooled reset time", "%1 used, %2 in %3",
                     usageText, resetCaption, pool.texts.duration(reset, pool.nowMs))
            : i18nc("@info:accessible usage and its reset time", "%1 used, resets in %2", usageText, pool.texts.duration(reset, pool.nowMs))
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Detail {
                Accessible.ignored: true
                text: row.label
            }

            Text {
                Accessible.ignored: true
                text: row.usageText
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText
                color: row.barColor
            }

            Text {
                Accessible.ignored: true
                visible: row.resetText !== ""
                text: row.resetCaption ? i18nc("@info time until a pooled usage reset", "%1 · %2", row.resetText, row.resetCaption)
                                       : row.resetText
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText
                color: Style.dim(Kirigami.Theme.textColor)
            }
        }

        Rectangle {
            visible: Number.isFinite(row.window.percent)
            Layout.fillWidth: true
            implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
            radius: height / 2
            color: Qt.alpha(Kirigami.Theme.textColor, Style.TRACK)

            Rectangle {
                anchors.left: parent.left
                width: Number.isFinite(row.window.percent) ? parent.width * Math.min(100, Math.max(0, row.window.percent)) / 100 : 0
                height: parent.height
                radius: parent.radius
                color: row.barColor
            }
        }
    }

    ColumnLayout {
        id: snapshot
        width: pool.availableWidth
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: pool.edge
            Layout.rightMargin: pool.edge
            spacing: Kirigami.Units.smallSpacing

            Detail {
                visible: text !== ""
                text: pool.texts.poolWords.quality(pool.entry)
            }

            Detail {
                visible: pool.texts.poolWords.incomplete(pool.entry, pool.otherPeriods)
                text: i18nc("@info CLIProxyAPI usage snapshot", "Some readings are incomplete.")
            }

            Detail {
                visible: text !== ""
                text: pool.entry?.proxyStatus !== "connected" ? pool.texts.poolWords.sourceStatus(pool.entry?.proxyStatus)
                                                              : pool.entry?.lastError ?? ""
            }
        }

        ColumnLayout {
            visible: pool.innerLimit !== null || pool.otherPeriods.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: pool.edge
            Layout.rightMargin: pool.edge
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: pool.otherPeriods

                delegate: LimitRow {
                    required property var modelData

                    label: pool.periodLabel(modelData)
                    window: modelData
                    reset: modelData.period === "session" ? NaN : Limits.nextReset(modelData, pool.nowMs)
                    resetCaption: pool.texts.poolWords.resetCaption(modelData)
                    stale: pool.stale
                }
            }

            LimitRow {
                visible: pool.innerLimit !== null
                label: pool.innerLimit?.label ?? ""
                window: pool.innerLimit ?? ({ percent: 0 })
                reset: NaN
                stale: pool.stale
            }
        }

        Repeater {
            model: pool.accounts

            delegate: ColumnLayout {
                id: account
                objectName: "pooledAccount"
                required property var modelData
                required property int index
                readonly property string name: i18nc("@title:group anonymized quota account, %1 is its ordinal",
                                                    "Account %1", Format.whole(index + 1))

                Layout.fillWidth: true
                Layout.leftMargin: pool.edge
                Layout.rightMargin: pool.edge
                spacing: Kirigami.Units.largeSpacing

                Divider {
                    Layout.leftMargin: 0
                    Layout.rightMargin: 0
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 5
                        text: account.name
                        textFormat: Text.PlainText
                    }

                    Detail {
                        visible: text !== ""
                        horizontalAlignment: Text.AlignRight
                        text: {
                            const reading = account.modelData;
                            if (reading.state === "unavailable") {
                                return i18nc("@info:status usage of a pooled account", "Unavailable");
                            }
                            if (reading.state === "stale" || pool.entry.lastError !== undefined) {
                                return i18nc("@info:status usage of a pooled account", "Last known reading");
                            }
                            return "";
                        }
                    }
                }

                Repeater {
                    model: pool.accountRows(account.modelData)

                    delegate: LimitRow {
                        required property var modelData

                        label: modelData.label
                        window: modelData.window
                        reset: window.resetsAt ?? NaN
                        stale: account.modelData.state === "stale" || pool.entry.lastError !== undefined
                        Accessible.name: i18nc("@info:accessible account name and window", "%1, %2", account.name, label)
                    }
                }

                BankedResets {
                    plain: true
                    banked: account.modelData.bankedResets ?? null
                    texts: pool.texts
                    nowMs: pool.nowMs
                }

                CreditsRemaining {
                    credit: pool.showCredits ? account.modelData.credits ?? null : null
                    plain: true
                }
            }
        }

        Item {
            Layout.preferredHeight: Kirigami.Units.smallSpacing
        }
    }
}
