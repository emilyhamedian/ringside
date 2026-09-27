import QtQuick
import QtTest

// Every popup against FakeMonitor in the states the gallery shows, loaded the
// way main.qml loads them. qmllint can't type the duck-typed monitor, so a
// script error in a popup binding, such as a JavaScript builtin Qt's engine
// lacks, only shows up at run time; any such warning fails the test.

Item {
    id: root
    width: 800
    height: 900

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    FakeMonitor {
        id: normal
    }

    FakeMonitor {
        id: hot
        cpuTemperature: 92
    }

    FakeMonitor {
        id: asleep
        gpuOuter.phase: "asleep"
    }

    FakeMonitor {
        id: resting
        gpuOuter.phase: "resting"
    }

    FakeMonitor {
        id: integrated
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.power: NaN
        gpuInner.present: false
    }

    // The discrete GPU picked for the inner ring, asleep.
    FakeMonitor {
        id: innerAsleep
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.power: NaN
        gpuInner.kind: "discrete"
        gpuInner.name: "AMD Radeon RX 7700S"
        gpuInner.phase: "asleep"
        gpuInner.knownVramTotal: 8 * innerAsleep.gib
    }

    // Intel publishes no GPU temperature or VRAM.
    FakeMonitor {
        id: intel
        cpuModel: "Intel Core i7-12700H"
        gpuOuter.name: "NVIDIA GeForce RTX 3060 Laptop GPU"
        gpuOuter.temperatureLabel: ""
        gpuInner.name: "Intel Iris Xe Graphics"
        gpuInner.temperatureLabel: ""
        gpuInner.reportsTemperature: false
        gpuInner.reportsVram: false
        gpuInner.temperature: NaN
        gpuInner.vramUsed: NaN
        gpuInner.vramTotal: NaN
        gpuInner.knownVramTotal: NaN
    }

    // No pressure stall information and no swap.
    FakeMonitor {
        id: bare
        memoryPressure: NaN
        swapUsed: 0
        swapTotal: 0
        swapLabel: ""
    }

    Component {
        id: host
        Loader {}
    }

    TestCase {
        name: "Popups"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function test_popup_data() {
            return [
                { tag: "cpu", popup: "CpuPopup", monitor: normal },
                { tag: "cpuHot", popup: "CpuPopup", monitor: hot },
                { tag: "gpu", popup: "GpuPopup", monitor: normal },
                { tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep },
                { tag: "gpuResting", popup: "GpuPopup", monitor: resting },
                { tag: "gpuIntegratedOnly", popup: "GpuPopup", monitor: integrated },
                { tag: "gpuInnerAsleep", popup: "GpuPopup", monitor: innerAsleep },
                { tag: "gpuIntel", popup: "GpuPopup", monitor: intel },
                { tag: "memory", popup: "MemoryPopup", monitor: normal },
                { tag: "memoryWithoutPressureOrSwap", popup: "MemoryPopup", monitor: bare },
                { tag: "network", popup: "NetworkPopup", monitor: normal }
            ];
        }
        function test_popup(data) {
            const loader = createTemporaryObject(host, root);
            verify(loader);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + data.popup + ".qml"),
                             { monitor: data.monitor });
            compare(loader.status, Loader.Ready);
            waitForRendering(loader.item);
            verify(loader.item.implicitWidth > 0);
            verify(loader.item.implicitHeight > 0);
        }
    }
}
