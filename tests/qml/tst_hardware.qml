// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/hardware.js" as Hardware

TestCase {
    name: "Hardware"

    // A choice is a ksystemstats id, "none", or "" for automatic. Turning
    // the outer ring off keeps the GPU that automatic would put inside,
    // which then takes the only ring rather than sit inside nothing.
    function test_assignGpus_data() {
        const discrete0 = { id: "gpu0", kind: "discrete" };
        const integrated0 = { id: "gpu0", kind: "integrated" };
        const discrete1 = { id: "gpu1", kind: "discrete" };
        const integrated1 = { id: "gpu1", kind: "integrated" };
        return [
            { tag: "discreteOutsideIntegratedInside", gpus: [integrated0, discrete1], outer: "", inner: "",
              expected: ["gpu1", "gpu0"] },
            { tag: "singleGpuHasNoInner", gpus: [discrete0], outer: "", inner: "", expected: ["gpu0", null] },
            { tag: "explicitIds", gpus: [discrete0, integrated1], outer: "gpu1", inner: "gpu0", expected: ["gpu1", "gpu0"] },
            { tag: "noneOnOuterKeepsTheInnerGpu", gpus: [discrete0, integrated1], outer: "none", inner: "",
              expected: ["gpu1", null] },
            // Two of a kind keep their order, so the second is the inner one.
            { tag: "noneOnOuterWithTwoDiscrete", gpus: [discrete0, discrete1], outer: "none", inner: "",
              expected: ["gpu1", null] },
            { tag: "noneOnOuterWithASingleGpu", gpus: [discrete0], outer: "none", inner: "", expected: [null, null] },
            { tag: "noneOnInnerLeavesOuterAlone", gpus: [discrete0, integrated1], outer: "", inner: "none",
              expected: ["gpu0", null] },
            { tag: "sameIdTwiceDropsTheInner", gpus: [discrete0, integrated1], outer: "gpu0", inner: "gpu0",
              expected: ["gpu0", null] },
            { tag: "unknownIdFallsBackToAVisibleGpu", gpus: [discrete0], outer: "bogus", inner: "", expected: ["gpu0", null] },
            { tag: "noGpus", gpus: [], outer: "", inner: "", expected: [null, null] },
            { tag: "undefinedListIsEmpty", gpus: undefined, outer: "", inner: "", expected: [null, null] }
        ];
    }
    function test_assignGpus(data) {
        const result = Hardware.assignGpus(data.gpus, data.outer, data.inner);
        compare([result.outer, result.inner].map(g => g ? g.id : null), data.expected);
    }

    // Free comes from "application", not from total - used - cache: the
    // cache reading overlaps "used" (shared memory, unreclaimable slab).
    function test_memoryParts_data() {
        const MiB = 1048576;
        return [
            // Readings from a real machine. Free is MemFree, 4.8 GiB;
            // taking cache and buffer from what "used" leaves gives 3.4.
            { tag: "cacheOverlapsUsed", total: 29211537408, used: 12196216832, application: 10655145984,
              cache: 13416001536, buffer: 16384, free: 5140373504, cached: 11874947072 },
            // Reserved pages put MemFree above MemAvailable; free stops at
            // what "used" leaves and nothing is cached.
            { tag: "memFreeAboveAvailable", total: 16384 * MiB, used: 15872 * MiB, application: 15462 * MiB,
              cache: 307 * MiB, buffer: 0, free: 512 * MiB, cached: 0 },
            { tag: "bufferNaNCountsAsNone", total: 16384 * MiB, used: 8192 * MiB, application: 6144 * MiB,
              cache: 4096 * MiB, buffer: NaN, free: 6144 * MiB, cached: 2048 * MiB },
            // Sensors sampled at different moments can overshoot the total.
            { tag: "readingsOutOfStepClampFreeAtZero", total: 16384 * MiB, used: 8192 * MiB, application: 12000 * MiB,
              cache: 6000 * MiB, buffer: 0, free: 0, cached: 8192 * MiB }
        ];
    }
    function test_memoryParts(data) {
        const parts = Hardware.memoryParts(data.total, data.used, data.application, data.cache, data.buffer);
        compare(parts.free, data.free);
        compare(parts.cached, data.cached);
        compare(data.used + parts.cached + parts.free, data.total);
    }

    // Before the first sample every reading is NaN.
    function test_memoryPartsWithoutReadingsIsNaN() {
        const parts = Hardware.memoryParts(NaN, NaN, NaN, NaN, NaN);
        verify(Number.isNaN(parts.free));
        verify(Number.isNaN(parts.cached));
        verify(Number.isNaN(Hardware.memoryParts(16e9, 8e9, NaN, 4e9, 0).free));
    }
}
