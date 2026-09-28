// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/items.js" as Items

TestCase {
    name: "Items"

    function test_isUsage_data() {
        return [
            { tag: "claude", item: "claude", expected: true },
            { tag: "codex", item: "codex", expected: true },
            { tag: "cpu", item: "cpu", expected: false },
            { tag: "gpu", item: "gpu", expected: false },
            { tag: "memory", item: "memory", expected: false },
            { tag: "network", item: "network", expected: false },
            { tag: "disk", item: "disk", expected: false },
            { tag: "unknown", item: "bogus", expected: false }
        ];
    }
    function test_isUsage(data) {
        compare(Items.isUsage(data.item), data.expected);
    }

    function test_isRing_data() {
        return [
            { tag: "cpu", item: "cpu", expected: true },
            { tag: "gpu", item: "gpu", expected: true },
            { tag: "memory", item: "memory", expected: true },
            { tag: "claude", item: "claude", expected: true },
            { tag: "codex", item: "codex", expected: true },
            { tag: "network", item: "network", expected: false },
            { tag: "disk", item: "disk", expected: false },
            { tag: "unknown", item: "bogus", expected: false }
        ];
    }
    function test_isRing(data) {
        compare(Items.isRing(data.item), data.expected);
    }

    function test_orderOnEmptyStoredIsTheDefaultOrder() {
        compare(Items.order([]), ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
    }

    function test_orderOnUndefinedStoredIsTheDefaultOrder() {
        compare(Items.order(undefined), ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
    }

    function test_orderKeepsStoredOrderFirstThenAppendsTheRest() {
        compare(Items.order(["network", "cpu"]), ["network", "cpu", "gpu", "memory", "disk", "claude", "codex"]);
    }

    function test_orderDropsUnknownIds() {
        compare(Items.order(["bogus", "cpu"]), ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
    }

    function test_orderDedupesRepeatedIds() {
        compare(Items.order(["cpu", "cpu", "gpu"]), ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
    }

    // A stored order without Claude or Codex leaves them trailing, like any
    // other item the order doesn't mention; an order that already lists one
    // keeps it in place.
    function test_orderWithoutAiItemsAppendsThemLast() {
        compare(Items.order(["disk", "network"]), ["disk", "network", "cpu", "gpu", "memory", "claude", "codex"]);
    }

    function test_orderAlreadyListingAnAiItemKeepsItsPosition() {
        compare(Items.order(["claude", "cpu"]), ["claude", "cpu", "gpu", "memory", "network", "disk", "codex"]);
    }

    function test_hiddenOnEmptyStoredOptsOutBothAiItems() {
        compare(Items.hidden([], []), ["claude", "codex"]);
    }

    function test_hiddenOnUndefinedArgsOptsOutBothAiItems() {
        compare(Items.hidden(undefined, undefined), ["claude", "codex"]);
    }

    function test_hiddenAiItemListedInOrderStaysOn() {
        compare(Items.hidden(["cpu", "claude"], []), ["codex"]);
    }

    function test_hiddenKeepsStoredHiddenAndDedupesUnknownIds() {
        compare(Items.hidden(["cpu"], ["disk", "disk", "bogus"]), ["disk", "claude", "codex"]);
    }

    // Explicitly hiding an AI item that the order also lists keeps it off:
    // the hidden list always wins.
    function test_hiddenExplicitlyHiddenAiItemStaysHiddenEvenWhenOrdered() {
        compare(Items.hidden(["claude", "cpu"], ["claude"]), ["claude", "codex"]);
    }

    function test_enabledOnEmptyStoredIsEverySystemItem() {
        compare(Items.enabled([], []), ["cpu", "gpu", "memory", "network", "disk"]);
    }

    function test_enabledWithAnAiItemInTheStoredOrder() {
        compare(Items.enabled(["claude", "cpu"], []), ["claude", "cpu", "gpu", "memory", "network", "disk"]);
    }

    function test_enabledRespectsAnExplicitlyHiddenSystemItem() {
        compare(Items.enabled(["cpu", "disk"], ["disk"]), ["cpu", "gpu", "memory", "network"]);
    }
}
