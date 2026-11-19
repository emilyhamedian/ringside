// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/limits.js" as Limits
import "../code/pace.js" as Pace
import "../code/providers.js" as Providers
import "../code/style.js" as Style
import ".."

// The popup for a Claude, Codex, Kimi or OpenCode Go item. The header shows
// the limit the ring tracks, a week or (for Kimi and OpenCode Go) a month,
// and the time until it resets. Below it are a bar for each model's own
// limit and for each shorter limit the plan has (the five-hour limit, and a
// weekly limit beside a monthly one), then a graph of the window so far.
// Under the graph are a line on where the current pace leads and, while the
// account has any, a line of tickets for its banked resets.
// A failed check is said under the header, with the last reading kept in
// grey for as long as the panel keeps it; once the panel's ring is struck,
// so is the header's, and the status under it is all the popup shows. A
// signed-out CLI is said in a line there. While the first check runs the
// header's ring waits and says so. A limit that started over early is told
// under the header for a day, or until the popup has shown it once. While
// the provider's setting allows it, the footer holds the session starter's
// switches, one for each window the plan lets Ringside start.
PopupPage {
    id: popup

    required property string item

    readonly property var usage: monitor.usage
    readonly property var entry: usage.entry(item)
    readonly property var weekly: entry && entry.weekly ? entry.weekly : null
    readonly property bool pooled: Limits.pooled(entry)
    readonly property real nextReset: pooled ? Limits.nextReset(weekly, nowMs) : weekly?.resetsAt ?? NaN
    // Kimi's and OpenCode Go's limits span a month; the words for them say
    // so, before a first reading too.
    readonly property bool monthly: words.monthly(weekly) || Providers.FACTS[item].monthly === true
    readonly property var innerLimit: usage.inner(item)
    // The last check failed. Its reading stays, greyed, until it is struck
    // (see UsageData.struck()), and then nothing of it is shown.
    readonly property bool failed: entry !== null && entry.lastError !== undefined
    readonly property bool struck: usage.struck(item, nowMs)
    readonly property bool greyShown: failed && !struck || Limits.allStale(entry)
    readonly property bool loading: usage.loading(item)
    // All models first, then every model's own limit, whichever the ring shows.
    readonly property var limits: weekly && !struck && !pooled
        ? [Object.assign({}, weekly, { id: "", label: i18nc("@label the weekly limit shared by every model", "All models") })]
            .concat(Array.from(entry.scoped ?? []))
        : []
    // The plan's limits that are shorter than the ring's, shown as bars: the
    // five-hour limit, and the weekly limit beside OpenCode Go's or an older
    // Kimi plan's monthly one. A window whose reset has passed since the
    // reading shows 0%. An idle five-hour window shows 0% and no reset time,
    // because an idle account can report a reset one window after the
    // request (see session_running() in usage.py).
    readonly property var shorter: {
        if (limits.length === 0) {
            return [];
        }
        const rows = [];
        const add = (window, label) => {
            const reset = window ? window.resetsAt : NaN;
            const ended = Format.usable(reset) && reset * 1000 <= nowMs;
            const percent = window && !ended ? window.percent : 0;
            const rolling = window && percent === 0 && Math.abs(reset - entry.fetchedAt - window.windowSeconds) <= 120;
            rows.push({ id: "", label: label, percent: percent,
                        resetsAt: Format.usable(reset) && !ended && !rolling ? reset : NaN });
        };
        // Claude reports null when no session is running. The key is missing
        // when the plan has no five-hour limit, or the reply couldn't be read.
        if (entry.session !== undefined) {
            add(entry.session, i18nc("@label a limit on the usage in any five hours", "5-hour limit"));
        }
        if (entry.week) {
            add(entry.week, i18nc("@label the weekly limit, under a monthly one", "Weekly limit"));
        }
        return rows;
    }
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
    readonly property var paceWords: paceEvent ? paceLineWords(limits[paceEvent.index], paceEvent.p) : null
    // Stepped by the timer below, for the countdowns and the paces, and
    // with each report, so the check that finds a reading too old strikes it.
    property real nowMs: Date.now()
    onEntryChanged: nowMs = Date.now()

    // When a limit on pace to run out does, as the pace line and the
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
        return words.weekdayTime(nearest <= limit.resetsAt - 60 ? nearest : down, popup.weekly, popup.nowMs);
    }

    // The pace line's caption and reading for `limit` and its pace `p`. The
    // line describes the ring's limit unless its caption names a model.
    function paceLineWords(limit, p) {
        const model = limit.id !== "" ? limit.label : "";
        switch (p.state) {
        case "reached":
            return {
                caption: model ? i18nc("@title:group over when a model's limit was used up, e.g. FABLE RAN OUT", "%1 ran out", model)
                               : i18nc("@title:group over when the weekly or monthly limit was used up", "Ran out"),
                value: Format.usable(p.reachedAt) ? words.weekdayTime(Math.round(p.reachedAt / 60) * 60, popup.weekly, popup.nowMs) : "–",
                unit: ""
            };
        case "out":
            return {
                // While checks are failing, the run-out is projected from a
                // reading that may be hours old, and can already be in the
                // past. Then the limit may already have run out.
                caption: p.runOut <= popup.nowMs / 1000
                    ? (model ? i18nc("@title:group at the rate of a reading hours old, over when a model's limit would already have been used up, e.g. FABLE MAY HAVE RUN OUT",
                                     "%1 may have run out", model)
                             : i18nc("@title:group at the rate of a reading hours old, over when the weekly or monthly limit would already have been used up",
                                     "May have run out"))
                    : (model ? i18nc("@title:group over when a model's limit runs out, before the reset, at the rate so far, e.g. FABLE RUNS OUT", "%1 runs out", model)
                             : i18nc("@title:group over when the weekly or monthly limit runs out, before the reset, at the rate so far", "Runs out")),
                value: popup.runOutWhen(limit, p),
                unit: ""
            };
        case "lasts":
            // Only the ring's limit reaches this state; a model's limit is
            // only mentioned when it runs out or has run out.
            return {
                caption: i18nc("@title:group over the share of the weekly or monthly limit used by the reset at the rate so far, e.g. 93% by the reset", "At this pace"),
                value: i18nc("@info a percentage", "%1%", Format.percent(p.atReset)),
                unit: i18nc("@info:label after the share of the limit used by the reset at the rate so far, e.g. 93% by the reset", "by the reset")
            };
        }
        return null;
    }

    function tone(level) {
        return greyShown ? Style.dim(Kirigami.Theme.textColor) : Style.levelColor(level, Kirigami.Theme);
    }

    systemMonitorShown: false
    readonly property bool starterShown: !pooled && !usage.starterPaused(item)
        && usage.starterEnabled(item) && usage.startable(item).length > 0
    readonly property var affinity: pooled ? entry?.affinity : null
    readonly property bool affinityShown: typeof affinity?.enabled === "boolean"
    footerLeadingShown: starterShown || affinityShown
    footerLeading: [
        StarterSwitch {
            visible: popup.starterShown
            item: popup.item
            usage: popup.usage
            nowMs: popup.nowMs
            texts: words
        },
        RowLayout {
            visible: popup.affinityShown
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Layout.topMargin
            spacing: Kirigami.Units.largeSpacing

            Text {
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: i18nc("@label CLIProxyAPI routing setting", "Session affinity")
                color: Style.dim(Kirigami.Theme.textColor)
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: {
                    const affinity = popup.affinity;
                    if (affinity?.enabled === true) {
                        const ttl = affinity.ttlSeconds;
                        const duration = Number.isFinite(ttl) && ttl > 0
                            ? words.duration(popup.nowMs / 1000 + ttl, popup.nowMs) : "";
                        return duration || i18nc("@info:status session affinity", "On");
                    }
                    return affinity?.enabled === false ? i18nc("@info:status session affinity", "Off") : "";
                }
                color: Kirigami.Theme.textColor
            }
        }
    ]

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
        ringValue: !popup.struck ? popup.weekly?.percent ?? NaN : NaN
        ringInner: popup.pooled && !popup.struck ? popup.innerLimit : null
        ringCancelled: popup.struck
        ringStale: popup.greyShown
        ringLoading: popup.loading
        title: words.providerName(popup.item)
        // As many as the reading had, whether or not they are shown; how
        // many there are isn't known until the first check is done.
        subtitle: popup.loading
            ? i18nc("@info under Claude, Codex, Kimi or OpenCode Go: the first check of the limits since Ringside started is running", "Checking your usage…")
            : popup.pooled ? words.poolWords.sourceName
            : popup.monthly
            ? i18ncp("@info under Kimi or OpenCode Go: what the popup shows", "Monthly limit", "Monthly limits",
                     Math.max(1, popup.limits.length, popup.entry && popup.entry.scoped ? popup.entry.scoped.length + 1 : 0))
            : i18ncp("@info under Claude or Codex: what the popup shows", "Weekly limit", "Weekly limits",
                     Math.max(1, popup.limits.length, popup.entry && popup.entry.scoped ? popup.entry.scoped.length + 1 : 0))
        parts: popup.weekly && !popup.struck ? words.countdownParts(popup.nextReset, popup.nowMs) : []
        // With no reading shown, a failed check says so under the header,
        // and a lone dash here would only look unfinished.
        value: popup.weekly && !header.partsShown && !popup.failed ? "–" : ""
        // Plain whatever the reading: the ring and bars carry the level.
        caption: header.partsShown ? (popup.pooled ? words.poolWords.resetCaption(popup.weekly)
            : i18nc("@info:label under the time left, e.g. 2d 21h until reset", "until reset")) : ""
        accessibleValue: header.partsShown
            ? (popup.pooled ? i18nc("@info:accessible time and pooled reset caption", "%1 · %2",
                                    words.duration(popup.nextReset, popup.nowMs), header.caption)
               : i18nc("@info:accessible the time left until the weekly or monthly reset, e.g. 5 days 18 hours until reset", "%1 until reset",
                        words.duration(popup.nextReset, popup.nowMs)))
            : ""
    }

    UsagePool {
        visible: popup.pooled
        Layout.maximumHeight: Math.max(0, popup.room - header.implicitHeight - header.Layout.topMargin
            - header.Layout.bottomMargin - popup.footerHeight - Kirigami.Units.smallSpacing)
        entry: popup.pooled ? popup.entry : null
        innerLimit: popup.pooled ? popup.innerLimit : null
        texts: words
        nowMs: popup.nowMs
        showCredits: popup.usage.showCredits
    }

    // Shown only beside a check that worked, so never with CheckStatus.
    ResetNotice {
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
        window: popup.loading || popup.pooled ? null : popup.usage.earlyReset(popup.item, popup.nowMs)
        texts: words
        nowMs: popup.nowMs
    }

    // Why there is nothing to show.
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        visible: text !== ""
        text: {
            const e = popup.entry;
            if (popup.loading || popup.pooled) {
                return "";
            }
            if (!e || e.status === "signed_out") {
                return popup.usage.helperError
                    || words.signInHint(popup.item);
            }
            return "";
        }
        color: Style.dim(Kirigami.Theme.textColor)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
    }

    // Set off from the header by about what sets it off from the bars.
    CheckStatus {
        visible: popup.failed && !popup.pooled
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
        item: popup.item
        usage: popup.usage
        entry: popup.entry
        struck: popup.struck
        texts: words
        nowMs: popup.nowMs
    }

    // A bar for every limit except the ring's own.
    ColumnLayout {
        id: barsColumn
        visible: popup.weekly !== null && popup.limits.length + popup.shorter.length > 1
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.75)
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            // Counted, as PopupHeader counts its parts, so a row keeps its
            // bar as the readings change and the bar can move to them.
            model: popup.limits.length + popup.shorter.length

            delegate: ColumnLayout {
                id: row

                required property int index
                // Every row has a bar except the ring's own limit.
                readonly property bool barred: index > 0
                // Put the shorter windows before the model-specific bars.
                readonly property bool short: barred && index <= popup.shorter.length
                readonly property var limit: (short ? popup.shorter[index - 1] : popup.limits[Math.max(0, index - popup.shorter.length)])
                    ?? ({ id: "", label: "", percent: NaN, resetsAt: NaN })
                readonly property real reading: Math.max(0, Math.min(100, limit.percent))
                // When the limit resets: for a shorter limit while it runs,
                // and for a model's limit that resets apart from the week.
                readonly property string resets: short
                    ? (Format.usable(limit.resetsAt) ? words.countdown(limit.resetsAt, popup.nowMs) : "")
                    : limit.id !== "" && popup.weekly && Math.abs(limit.resetsAt - popup.weekly.resetsAt) >= 60
                    ? words.countdown(limit.resetsAt, popup.nowMs) : ""
                // The level of the bar as drawn, as RingGauge.drawnLevel has it.
                readonly property int level: Format.level(Number.isFinite(reading) ? bar.shown + reading - Math.round(reading) : NaN)

                // The bar and its percentage move to a new reading as a ring
                // does. The ring's own row has no bar, so it jumps at once.
                Follower {
                    id: bar
                    target: Number.isFinite(row.reading) ? Math.round(row.reading) : 0
                    settle: row.barred && Style.animated(Kirigami.Units) ? Kirigami.Units.veryLongDuration : 0
                    // A quarter of a pixel of the bar.
                    precision: 25 / Math.max(1, track.width)
                }

                visible: row.barred
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
                    color: Qt.alpha(Kirigami.Theme.textColor, Style.TRACK)

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
        }
    }

    GridLayout {
        visible: popup.limits.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        // Straight under the header, as far from it as the other popups'
        // tiles are; under the bars, their own wider margin keeps it apart.
        Layout.topMargin: barsColumn.visible ? 0 : Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: credits.shown ? Kirigami.Units.largeSpacing : Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 1
        rowSpacing: Kirigami.Units.largeSpacing

        UsageGraph {
            id: week
            texts: words
            window: popup.weekly
            modelWindow: popup.innerLimit
            monthly: popup.monthly
            nowMs: popup.nowMs
            pollAt: popup.pollAt
            failed: popup.greyShown
            grey: popup.greyShown
            // The run-out named by the pace line, if the graph draws its limit.
            projected: {
                const e = popup.paceEvent;
                return !e ? "" : e.index === 0 ? "main"
                     : popup.innerLimit !== null && popup.limits[e.index].id === popup.innerLimit.id ? "second" : "";
            }
        }

        // The pace line under the graph: the share of the ring's limit the
        // current pace will use by the reset, or when a limit runs out. When
        // the graph draws that run-out, the line's dashes tie its time to the
        // graph's dashed line, and the graph shows no time of its own.
        LineTile {
            objectName: "pace"
            visible: popup.paceWords !== null
            caption: popup.paceWords?.caption ?? ""
            reading: paceReading
            readingCap: Style.capHeight(bodyMetrics, bodyCap)
            keyed: popup.paceEvent?.p.state === "out" && week.projected !== ""
            // As tall as the tickets' row, so the two lines match.
            minimumRowHeight: resetTickets.ticketHeight
            keyColor: {
                const tone = popup.tone(popup.paceEvent ? Format.level(popup.limits[popup.paceEvent.index].percent) : 0);
                return Qt.alpha(tone, 0.6 * tone.a);
            }

            // Greyed out while the reading is out of date, like the bars.
            Reading {
                id: paceReading
                value: popup.paceWords?.value ?? ""
                unit: popup.paceWords?.unit ?? ""
                color: popup.greyShown ? Style.dim(Kirigami.Theme.textColor) : Kirigami.Theme.textColor
            }

            FontMetrics {
                id: bodyMetrics
                font: Kirigami.Theme.defaultFont
            }

            TextMetrics {
                id: bodyCap
                font: Kirigami.Theme.defaultFont
                text: "H"
            }
        }

        // The banked resets, on their own line under the pace line and laid
        // out the same way.
        BankedResets {
            id: resetTickets
            banked: popup.struck ? null : popup.entry?.bankedResets ?? null
            texts: words
            nowMs: popup.nowMs
            minimumRowHeight: Math.ceil(paceReading.implicitHeight)
        }
    }

    // Below the other lines, with the same gap between them. It stays when
    // the readings are struck out, because the balance is checked separately.
    CreditsRemaining {
        id: credits
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        credit: popup.pooled ? null : popup.usage.credit(popup.item)
        minimumRowHeight: resetTickets.ticketHeight
    }
}
