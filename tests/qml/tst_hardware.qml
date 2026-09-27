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
    function test_assignGpusNoneOnOuterPromotesTheOtherGpu() {
        var result = Hardware.assignGpus([gpu("gpu0", "discrete"), gpu("gpu1", "integrated")], "none", "");
        compare(result.outer.id, "gpu0");
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
}
