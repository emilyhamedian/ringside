// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/limits.js" as Limits

TestCase {
    name: "Limits"

    function opus() { return { id: "opus", label: "Opus" }; }
    function sonnet() { return { id: "sonnet", label: "Sonnet" }; }

    function test_pickAutomaticWithASingleLimitReturnsIt() {
        compare(Limits.pick([opus()], ""), opus());
    }

    function test_pickAutomaticWithSeveralLimitsReturnsNone() {
        compare(Limits.pick([opus(), sonnet()], ""), null);
    }

    function test_pickNoneReturnsNullEvenWithLimitsReported() {
        compare(Limits.pick([opus()], "none"), null);
    }

    function test_pickById() {
        compare(Limits.pick([opus(), sonnet()], "sonnet"), sonnet());
    }

    function test_pickMissingIdReturnsNull() {
        compare(Limits.pick([opus()], "bogus"), null);
    }

    function test_pickWithoutScopedDataReturnsNullRegardlessOfChoice_data() {
        return [
            { tag: "automatic", scoped: null, choice: "" },
            { tag: "byId", scoped: undefined, choice: "opus" },
            { tag: "none", scoped: null, choice: "none" }
        ];
    }
    function test_pickWithoutScopedDataReturnsNullRegardlessOfChoice(data) {
        compare(Limits.pick(data.scoped, data.choice), null);
    }

    function test_pickWithAnEmptyScopedListReturnsNull() {
        compare(Limits.pick([], ""), null);
        compare(Limits.pick([], "opus"), null);
    }

    function test_knownMapsEveryReportedLimitAsReported() {
        const result = Limits.known({ claude: { scoped: [opus()] } }, {}, {});
        compare(result.claude, [{ id: "opus", label: "Opus", reported: true }]);
        // Every provider is always present, even without a reading.
        compare(result.codex, []);
    }

    function test_knownKeepsAPickedUnreportedLimitsStoredLabel() {
        const providers = { claude: { scoped: [opus()] } };
        const stored = { claude: [{ id: "old", label: "Old Model" }] };
        const choices = { claude: "old" };
        compare(Limits.known(providers, stored, choices), {
            claude: [{ id: "opus", label: "Opus", reported: true },
                     { id: "old", label: "Old Model", reported: false }],
            codex: []
        });
    }

    function test_knownUnreportedPickWithoutAStoredLabelFallsBackToItsId() {
        const result = Limits.known({ claude: { scoped: [opus()] } }, {}, { claude: "missing" });
        compare(result.claude, [{ id: "opus", label: "Opus", reported: true },
                                 { id: "missing", label: "missing", reported: false }]);
    }

    function test_knownProviderWithoutAReadingKeepsWhatWasStored() {
        const stored = { claude: [{ id: "x", label: "X" }] };
        compare(Limits.known({}, stored, {}), { claude: [{ id: "x", label: "X" }], codex: [] });
    }

    // Automatic ("") and none never add an extra unreported entry: only a
    // choice that names a specific, no-longer-reported limit does.
    function test_knownAutomaticOrNoneChoiceNeverAddsAnEntry_data() {
        return [
            { tag: "automatic", choice: "" },
            { tag: "none", choice: "none" }
        ];
    }
    function test_knownAutomaticOrNoneChoiceNeverAddsAnEntry(data) {
        const providers = { claude: { scoped: [opus()] } };
        const stored = { claude: [{ id: "old", label: "Old Model" }] };
        const result = Limits.known(providers, stored, { claude: data.choice });
        compare(result.claude, [{ id: "opus", label: "Opus", reported: true }]);
    }
}
