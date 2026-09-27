import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"

// The panel strip with FakeMonitor's readings: its width holds while values
// change, a thin vertical panel's rates fit, and every cell describes its
// readings in words.
Item {
    id: root
    width: 800
    height: 600

    readonly property color hotColor: Kirigami.Theme.negativeTextColor

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: stripComponent
        Strip {
            items: ["cpu", "gpu", "memory", "network", "disk"]
            vertical: false
            thickness: 46
            ringSize: 30
            ringsOnly: []
        }
    }

    TestCase {
        id: testCase
        name: "Strip"
        when: windowShown

        property var monitor: null
        property var strip: null

        function init() {
            monitor = monitorComponent.createObject(testCase);
        }

        // The strip goes first, so its bindings never see the monitor gone.
        function cleanup() {
            strip?.destroy();
            wait(0);
            monitor.destroy();
            strip = null;
        }

        function makeStrip(properties) {
            strip = stripComponent.createObject(root, Object.assign({ monitor: monitor }, properties));
            waitForRendering(strip);
            return strip;
        }

        // Layouts settle on the next polish, so read after a render.
        function widthAfter(strip, change) {
            change();
            waitForRendering(strip);
            return strip.implicitWidth;
        }

        function test_widthHoldsAsReadingsChange_data() {
            return [{ tag: "bits", bits: true }, { tag: "bytes", bits: false }];
        }

        function test_widthHoldsAsReadingsChange(data) {
            monitor.networkBits = data.bits;
            const strip = makeStrip({});
            const width = strip.implicitWidth;
            const changes = [
                () => { monitor.networkDown = 0; monitor.networkUp = 0; },
                () => { monitor.networkDown = 60; monitor.networkUp = 20; },
                () => { monitor.networkDown = 130; monitor.networkUp = 300; },
                () => { monitor.networkDown = 1.3e7; monitor.networkUp = 1023; },
                () => { monitor.networkDown = NaN; monitor.networkUp = NaN; },
                () => { monitor.diskRead = 0; monitor.diskWrite = 1e9; },
                () => { monitor.memoryUsed = 9.6 * monitor.gib; },
                () => { monitor.memoryUsed = NaN; },
                () => { monitor.cpuTemperature = NaN; },
                () => { monitor.fahrenheit = true; monitor.cpuTemperature = 38; },
                () => { monitor.cpuTemperature = 140; },
                () => { monitor.gpuOuter.phase = "asleep"; },
                () => { monitor.gpuOuter.phase = "live"; monitor.gpuInner.phase = "asleep"; },
            ];
            for (let i = 0; i < changes.length; ++i) {
                compare(widthAfter(strip, changes[i]), width, "change " + i);
            }
        }

        function test_verticalRatesFit_data() {
            // Breeze gives an applet the panel's thickness less 8 px.
            return [34, 36, 40, 44, 48, 52, 60].map(width => ({ tag: String(width), width: width }));
        }

        function test_verticalRatesFit(data) {
            const strip = makeStrip({ vertical: true, width: data.width, thickness: data.width });
            for (const index of [3, 4]) {
                const rates = strip.cellAt(index).contentItem;
                // It fits, with a pixel of slack for hinting at the shrunk size,
                // or it has shrunk as far as it may. Where the floor lands
                // depends on the font, so the test doesn't pin it.
                const floor = Kirigami.Theme.smallFont.pointSize * 0.6;
                verify(rates.implicitWidth <= rates.availableWidth + 1 || Math.abs(rates.pointSize - floor) < 0.01,
                       rates.item + " " + rates.implicitWidth + " in " + rates.availableWidth + " at " + rates.pointSize);
            }
        }

        function test_innerAsleepSaysOff() {
            monitor.gpuInner.kind = "discrete";
            monitor.gpuInner.phase = "asleep";
            const strip = makeStrip({ items: ["gpu"] });
            const texts = [];
            const collect = item => {
                if (item.visible && item.text !== undefined && item.text !== "") {
                    texts.push(item.text);
                }
                item.children.forEach(collect);
            };
            collect(strip);
            verify(texts.includes("off"), JSON.stringify(texts));
            verify(!texts.includes("–"), JSON.stringify(texts));
            compare(strip.cellAt(0).description.split("\n")[1], "AMD Radeon 780M Graphics: Off");
        }

        function test_intelLeavesTemperatureOut() {
            monitor.gpuInner.reportsTemperature = false;
            monitor.gpuInner.temperature = NaN;
            const strip = makeStrip({ items: ["gpu"] });
            compare(strip.cellAt(0).description.split("\n")[1], "AMD Radeon 780M Graphics: Usage 3%");
        }

        function test_descriptions() {
            monitor.cpuTemperature = 80;
            const strip = makeStrip({});
            compare(strip.cellAt(0).Accessible.description, "Usage 23%, temperature 80 °C, warm");
            compare(strip.cellAt(2).Accessible.description, "13.4 GiB in use, 42%");
            compare(strip.cellAt(3).Accessible.description, "Down 24.8 Mb/s, up 1.2 Mb/s");
            compare(strip.cellAt(4).Accessible.description, "Read 12.0 MiB/s, write 3.4 MiB/s");
            monitor.cpuTemperature = NaN;
            compare(strip.cellAt(0).Accessible.description, "Usage 23%, temperature unavailable");
        }

        function test_hiddenTextShowsTooltipAndHeat() {
            monitor.cpuTemperature = 95;
            const strip = makeStrip({ vertical: true, width: 38, thickness: 38 });
            const cell = strip.cellAt(0);
            const area = cell.parent;
            verify(area.active);
            compare(area.mainText, "Processor");
            compare(area.subText, "Usage 23%, temperature 95 °C, hot");
            const gauge = cell.contentItem.children[0];
            compare(gauge.color, root.hotColor);
            verify(!strip.cellAt(3).parent.active, "rates keep their text");

            mouseMove(cell, cell.width / 2, cell.height / 2);
            verify(cell.containsMouse && area.containsMouse, "hover reaches the cell and the tooltip");
            strip.openItem = "cpu";
            verify(!area.active, "no tooltip over an open popup");
        }
    }
}
