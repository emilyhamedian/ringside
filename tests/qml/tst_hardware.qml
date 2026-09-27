import QtQuick
import QtTest
import "../../package/contents/ui/code/hardware.js" as Hardware

TestCase {
    name: "Hardware"

    function gpu(id, kind) {
        return { id: id, kind: kind };
    }

    function test_assignGpusPutsDiscreteOutsideAndIntegratedInside() {
        var result = Hardware.assignGpus([gpu("gpu0", "integrated"), gpu("gpu1", "discrete")], "", "");
        compare(result.outer.id, "gpu1");
        compare(result.outer.kind, "discrete");
        compare(result.inner.id, "gpu0");
        compare(result.inner.kind, "integrated");
    }

    function test_assignGpusSingleGpuHasNoInner() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete")], "", "");
        compare(result.outer.id, "gpu0");
        compare(result.inner, null);
    }

    function test_assignGpusHonoursExplicitIds() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "integrated")], "gpu1", "gpu0");
        compare(result.outer.id, "gpu1");
        compare(result.inner.id, "gpu0");
    }

    // "none" on the outer choice must not strand the only visible GPU as an
    // inner ring with nothing outside it.
    // Turning the outer ring off keeps the GPU that automatic would put
    // inside, which then takes the only ring.
    function test_assignGpusNoneOnOuterKeepsTheInnerGpu() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "integrated")], "none", "");
        compare(result.outer.id, "gpu1");
        compare(result.inner, null);
    }

    function test_assignGpusNoneOnOuterWithTwoDiscreteGpus() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "discrete")], "none", "");
        compare(result.outer.id, "gpu1");
        compare(result.inner, null);
    }

    function test_assignGpusNoneOnOuterWithASingleGpu() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete")], "none", "");
        compare(result.outer, null);
        compare(result.inner, null);
    }

    function test_assignGpusNoneOnInnerLeavesOuterAlone() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "integrated")], "", "none");
        compare(result.outer.id, "gpu0");
        compare(result.inner, null);
    }

    function test_assignGpusSameIdChosenTwiceDropsTheInner() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "integrated")], "gpu0", "gpu0");
        compare(result.outer.id, "gpu0");
        compare(result.inner, null);
    }

    function test_assignGpusUnknownIdFallsBackToAVisibleGpu() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete")], "bogus", "");
        compare(result.outer.id, "gpu0");
        compare(result.inner, null);
    }

    function test_assignGpusNoGpusAtAll() {
        var result = Hardware.assignGpus([], "", "");
        compare(result.outer, null);
        compare(result.inner, null);
    }

    function test_assignGpusUndefinedListIsTreatedAsEmpty() {
        var result = Hardware.assignGpus(undefined, "", "");
        compare(result.outer, null);
        compare(result.inner, null);
    }

    function test_swapLabel_data() {
        return [
            { tag: "both", kinds: ["zram", "disk"], expected: "zram + disk" },
            { tag: "zramOnly", kinds: ["zram"], expected: "zram" },
            { tag: "none", kinds: [], expected: "" },
            { tag: "undefined", kinds: undefined, expected: "" }
        ];
    }
    function test_swapLabel(data) {
        compare(Hardware.swapLabel(data.kinds), data.expected);
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
