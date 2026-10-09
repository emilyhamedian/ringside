// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/pace.js" as Pace
import "../code/style.js" as Style
import ".."

// Claude's or Codex's weekly limits: the all-models week in the header with
// the time left until it resets, a bar for it and for each model's own limit
// with a sentence under one of them on where the current pace leads, and
// the week so far as a graph. With one limit the header's ring is its bar.
// A failed check is said under the header, with the last reading kept in
// grey while its week lasts; a signed-out CLI in a line there.
// The footer holds the session starter's switch.
PopupPage {
    id: popup

    required property string item

    readonly property var usage: monitor.usage
    readonly property var entry: usage.entry(item)
    readonly property var weekly: entry && entry.weekly ? entry.weekly : null
    readonly property var innerLimit: usage.inner(item)
    readonly property bool claude: item === "claude"
    // The last check failed. Its reading stays, greyed, while its week
    // lasts; one from a week that has since reset has nothing left to say.
    readonly property bool failed: entry !== null && entry.lastError !== undefined
    readonly property bool weekOver: weekly !== null && weekly.resetsAt <= nowMs / 1000
    readonly property bool greyShown: failed && weekly !== null && !weekOver
    // A reading over two hours old says nothing certain about where the
    // week is heading, so its run-out goes.
    readonly property bool paceKept: !failed || nowMs / 1000 - entry.fetchedAt <= 7200
    // All models first, then every model's own limit, whichever the ring shows.
    readonly property var limits: weekly && !(failed && weekOver)
        ? [Object.assign({}, weekly, { id: "", label: i18nc("@label the weekly limit shared by every model", "All models") })]
            .concat(Array.from(entry.scoped ?? []))
        : []
    readonly property real pollAt: Pace.pollTime(entry, nowMs / 1000)
    // Each limit's projection, in the order of limits.
    readonly property var paces: limits.map(l => Pace.ofWindow(l, pollAt, nowMs / 1000))
    // The one thing worth saying about the pace, as { index, p } into limits:
    // every model locked out, else the soonest run-out of a limit not yet
    // reached (the one warning nothing else on screen gives), else a model's
    // reached limit, else how the week as a whole is going.
    readonly property var paceEvent: {
        const events = paces.map((p, index) => ({ index: index, p: p }));
        if (events.length === 0) {
            return null;
        }
        if (events[0].p.state === "reached") {
            return events[0];
        }
        const out = events.filter(e => e.p.state === "out").reduce((a, b) => !a || b.p.runOut < a.p.runOut ? b : a, null);
        return out ?? events.find(e => e.p.state === "reached") ?? (events[0].p.state !== "none" ? events[0] : null);
    }
    readonly property string paceText: paceEvent && paceKept ? paceSentence(limits[paceEvent.index], paceEvent.p) : ""
    // Stepped by the timer below, for the countdowns and the paces.
    property real nowMs: Date.now()

    // When a limit on pace to run out does, as the pace sentence and the
    // graph give it: to ten minutes on the clock it is shown in, which in a
    // zone such as Nepal's is not the UTC grid, since a projection to the
    // minute claims more than it knows. Rounded up, it could land on the
    // reset or after it, so there it rounds down, and stays at least a
    // minute before it.
    function runOutWhen(limit, p) {
        const second = Math.floor(p.runOut);
        const clock = words.zonedDate(second, popup.weekly);
        const down = second - (clock.getMinutes() * 60 + clock.getSeconds()) % 600;
        const nearest = p.runOut - down >= 300 ? down + 600 : down;
        return words.weekdayTime(nearest <= limit.resetsAt - 60 ? nearest : down, popup.weekly);
    }

    function paceSentence(limit, p) {
        const all = limit.id === "";
        switch (p.state) {
        case "reached": {
            const when = Format.usable(p.reachedAt) ? words.weekdayTime(Math.round(p.reachedAt / 60) * 60, popup.weekly) : "";
            return all ? (when ? i18nc("@info when the weekly limit was used up, e.g. Limit reached Sun 3:00 PM", "Limit reached %1", when)
                               : i18nc("@info the weekly limit is used up", "Limit reached"))
                       : (when ? i18nc("@info when a model's limit was used up, e.g. Fable limit reached Sun 3:00 PM", "%1 limit reached %2", limit.label, when)
                               : i18nc("@info a model's limit is used up, e.g. Fable limit reached", "%1 limit reached", limit.label));
        }
        case "out": {
            const when = popup.runOutWhen(limit, p);
            // Projected from a reading hours old, while checks fail, the
            // run-out can already lie behind now: then it may have happened.
            if (p.runOut <= popup.nowMs / 1000) {
                return !all ? i18nc("@info at the rate of a reading hours old, a model's limit would already be used up, e.g. Fable may already have run out Mon 5:50 PM",
                                    "%1 may already have run out %2", limit.label, when)
                     : popup.limits.length > 1 ? i18nc("@info at the rate of a reading hours old, every model's shared weekly limit would already be used up, e.g. All models may already have run out Mon 5:50 PM",
                                                       "All models may already have run out %1", when)
                     : i18nc("@info at the rate of a reading hours old, the weekly limit would already be used up, e.g. The weekly limit may already have run out Mon 5:50 PM",
                             "The weekly limit may already have run out %1", when);
            }
            // The shared limit is named too: under the first of several bars,
            // a bare "on pace to run out" could be read as being about a model.
            return !all ? i18nc("@info a model's limit runs out before the reset at the rate so far, e.g. Fable is on pace to run out Tue 3:30 AM",
                                "%1 is on pace to run out %2", limit.label, when)
                 : popup.limits.length > 1 ? i18nc("@info every model's shared weekly limit runs out before the reset at the rate so far, e.g. All models are on pace to run out Wed 12:20 PM",
                                                   "All models are on pace to run out %1", when)
                 : i18nc("@info the weekly limit runs out before the reset at the rate so far, e.g. The weekly limit is on pace to run out Wed 12:20 PM",
                         "The weekly limit is on pace to run out %1", when);
        }
        case "lasts":
            return i18nc("@info the share of the weekly limit used by the reset at the rate so far, e.g. On pace to use 93% by the reset",
                         "On pace to use %1 by the reset", i18nc("@info a percentage", "%1%", Format.percent(p.atReset)));
        }
        return "";
    }

    function tone(level) {
        return greyShown ? Style.dim(Kirigami.Theme.textColor)
             : level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
    }

    systemMonitorShown: false
    footerLeading: StarterSwitch {
        item: popup.item
        usage: popup.usage
        nowMs: popup.nowMs
        texts: words
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: popup.nowMs = Date.now()
    }

    PopupHeader {
        id: header
        ringValue: popup.weekly && !(popup.failed && popup.weekOver) ? popup.weekly.percent : NaN
        ringCancelled: popup.failed && !popup.greyShown
        ringStale: popup.greyShown
        title: popup.claude ? i18nc("@title", "Claude") : i18nc("@title", "Codex")
        // As many as the reading had, whether or not they are shown.
        subtitle: i18ncp("@info under Claude or Codex: what the popup shows", "Weekly limit", "Weekly limits",
                         Math.max(1, popup.limits.length, popup.entry && popup.entry.scoped ? popup.entry.scoped.length + 1 : 0))
        parts: popup.weekly ? words.countdownParts(popup.weekly.resetsAt, popup.nowMs) : []
        // With no reading in this week, a failed check says so under the
        // header, and a lone dash here would only look unfinished.
        value: popup.weekly && !header.partsShown && !popup.failed ? "–" : ""
        // The ring and bars carry the level; at the limit the countdown is
        // how long the lock-out lasts, and only then does it turn red. Once
        // the reset has passed there is none, and the dash stays plain. A
        // reading kept from a failed check may be out of date, so its
        // countdown stays plain too.
        valueColor: header.partsShown && popup.weekly.percent >= 100 && !popup.failed
            ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        caption: header.partsShown ? i18nc("@info:label under the time left, e.g. 2d 21h until reset", "until reset") : ""
        accessibleValue: header.partsShown
            ? i18nc("@info:accessible the time left until the weekly reset, e.g. 5 days 18 hours until reset", "%1 until reset",
                    words.duration(popup.weekly.resetsAt, popup.nowMs))
            : ""
    }

    // Why there is nothing to show.
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        visible: text !== ""
        text: {
            const e = popup.entry;
            if (!e || e.status === "signed_out") {
                return popup.usage.helperError
                    || (popup.claude ? i18nc("@info", "Run claude in a terminal to sign in.")
                                     : i18nc("@info", "Run codex in a terminal to sign in."));
            }
            return "";
        }
        color: Style.dim(Kirigami.Theme.textColor)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
    }

    CheckStatus {
        visible: popup.failed
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
        item: popup.item
        usage: popup.usage
        entry: popup.entry
        texts: words
        nowMs: popup.nowMs
    }

    // A bar per limit when there are several, with the pace sentence under
    // the bar it is about; with one limit, the sentence alone.
    ColumnLayout {
        id: barsColumn
        visible: popup.weekly !== null && (popup.limits.length > 1 || popup.paceText !== "")
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.75)
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            // Counted, as PopupHeader counts its parts, so a row keeps its
            // bar as the readings change and the bar can move to them.
            model: popup.limits.length

            delegate: ColumnLayout {
                id: row

                required property int index
                readonly property var limit: popup.limits[index] ?? ({ id: "", label: "", percent: NaN, resetsAt: NaN })
                readonly property real reading: Math.max(0, Math.min(100, limit.percent))
                // A model's limit that resets apart from the week says when.
                readonly property string resets: limit.id !== "" && popup.weekly
                    && Math.abs(limit.resetsAt - popup.weekly.resetsAt) >= 60
                    ? words.countdown(limit.resetsAt, popup.nowMs) : ""
                // The level of the bar as drawn, as RingGauge.drawnLevel has it.
                readonly property int level: Format.level(Number.isFinite(reading) ? bar.shown + reading - Math.round(reading) : NaN)

                // The bar and its percentage follow the reading as a ring
                // does, and at once with one limit, which has no bar.
                Follower {
                    id: bar
                    target: Number.isFinite(row.reading) ? Math.round(row.reading) : 0
                    settle: popup.limits.length > 1 && Kirigami.Units.longDuration > 1 ? Kirigami.Units.veryLongDuration : 0
                    // A quarter of a pixel of the bar.
                    precision: 25 / Math.max(1, track.width)
                }

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    visible: popup.limits.length > 1
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: row.limit.label
                    Accessible.description: words.percentText(row.limit.percent)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        Text {
                            Layout.fillWidth: true
                            text: row.limit.label
                            color: Kirigami.Theme.textColor
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignLeft
                        }

                        Text {
                            visible: row.resets !== ""
                            text: i18nc("@info time left until this limit resets, e.g. resets in 4d 2h", "resets in %1", row.resets)
                            color: Style.dim(Kirigami.Theme.textColor)
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            textFormat: Text.PlainText
                        }

                        Text {
                            text: i18nc("@info a percentage", "%1%", Format.percent(Number.isFinite(row.reading) ? bar.shown : NaN))
                            color: popup.tone(row.level)
                            font.family: Kirigami.Theme.defaultFont.family
                            font.features: ({ "tnum": 1 })
                            textFormat: Text.PlainText
                        }
                    }

                    Rectangle {
                        id: track
                        Layout.fillWidth: true
                        implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
                        radius: height / 2
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

                        Rectangle {
                            anchors.left: parent.left
                            width: parent.width * bar.shown / 100
                            height: parent.height
                            radius: parent.radius
                            // A kept reading greys as the header's ring does.
                            color: popup.greyShown ? Qt.alpha(Kirigami.Theme.textColor, 0.42) : popup.tone(row.level)
                        }
                    }
                }

                // Wrapped, so its height follows the popup's width: on Qt
                // 6.6 a host that sized the popup straight from the Loader's
                // preferred size, rather than a resize later as AppletPopup
                // does, reports a binding loop on preferredHeight.
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: popup.paceEvent !== null && popup.paceEvent.index === row.index ? popup.paceText : ""
                    color: popup.greyShown ? Style.dim(Kirigami.Theme.textColor) : Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }
    }

    // A week that reset with no reading since stays, as last week's.
    GridLayout {
        visible: popup.weekly !== null
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        // Straight under the header, as far from it as the other popups'
        // tiles are; under the bars, their own wider margin keeps it apart.
        Layout.topMargin: barsColumn.visible ? 0 : Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 1

        Tile {
            caption: popup.weekOver && popup.failed
                ? i18nc("@title:group the weekly window that has ended, with no reading since", "Last week")
                : i18nc("@title:group the current weekly window", "This week")
            // The rule's, so only while the graph draws one.
            graphTop: week.placed ? i18nc("@info a percentage", "%1%", Format.percent(100)) : ""
            foot: popup.innerLimit !== null ? allModels : week.foot
            detail: {
                const date = words.resetDate(popup.weekly);
                return !date ? ""
                     : popup.weekOver && popup.failed
                     ? i18nc("@title:group after LAST WEEK: when that week ended, e.g. · reset Sun 7:00 AM EDT", "· reset %1", date)
                     : i18nc("@title:group after THIS WEEK: when the week starts over, e.g. · resets Sun 7:00 AM EDT",
                             "· resets %1", date);
            }

            WeekGraph {
                id: week
                Layout.fillWidth: true
                window: popup.weekly
                secondWindow: popup.innerLimit
                nowMs: popup.nowMs
                pollAt: popup.pollAt
                failed: popup.failed && !popup.weekOver
                grey: popup.greyShown
                // The run-out the pace sentence names, if the graph draws that
                // limit: the week, or the model on the inner ring.
                projected: {
                    const e = popup.paceKept ? popup.paceEvent : null;
                    return !e ? "" : e.index === 0 ? "main"
                         : popup.innerLimit !== null && popup.limits[e.index].id === popup.innerLimit.id ? "second" : "";
                }
                runOutText: {
                    const e = popup.paceKept ? popup.paceEvent : null;
                    return e && e.p.state === "out" ? popup.runOutWhen(popup.limits[e.index], e.p) : "";
                }
            }

            RowLayout {
                visible: popup.innerLimit !== null
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

                Caption {
                    id: allModels
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the solid line", "— All models")
                }

                Caption {
                    Layout.fillWidth: true
                    text: popup.innerLimit ? i18nc("@label graph legend, the dashed line; %1 is a model", "- - %1",
                                                   popup.innerLimit.label) : ""
                }
            }
        }
    }
}
