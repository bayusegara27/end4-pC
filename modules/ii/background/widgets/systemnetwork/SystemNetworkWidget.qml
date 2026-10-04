import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    Component.onCompleted: ResourceUsage.consumers++
    Component.onDestruction: ResourceUsage.consumers--
    configEntryName: "systemNetwork"
    hoverEnabled: true

    // ── Standard Quickshell Grid ──
    readonly property real cardSpacing: 12
    readonly property real singleWidth: 132
    readonly property real cardHeight: 120

    readonly property real snapWidth1: singleWidth                      // 132
    readonly property real snapWidth2: singleWidth * 2 + cardSpacing     // 276
    readonly property real snapWidth3: singleWidth * 3 + cardSpacing * 2 // 420

    readonly property real snapHeight1: cardHeight                      // 120
    readonly property real snapHeight2: cardHeight * 2 + cardSpacing     // 252

    property string sizeMode: root.configEntry?.sizeMode ?? "2x2"

    property real widgetWidth: {
        switch (root.sizeMode) {
            case "1x1": return snapWidth1
            case "2x3": return snapWidth3
            default:    return snapWidth2
        }
    }
    property real widgetHeight: {
        switch (root.sizeMode) {
            case "1x1": return snapHeight1
            case "1x2": return snapHeight1
            default:    return snapHeight2
        }
    }

    readonly property real heightToggleDelta: (root.snapHeight2 - root.snapHeight1) * 0.3
    readonly property real wideThreshold: (root.snapWidth2 + root.snapWidth3) / 2

    function modeForDrag(dx, dy, startWidth) {
        var mid = (root.snapWidth1 + root.snapWidth2) / 2
        var newWidth = startWidth + dx

        if (newWidth < mid) return "1x1"

        if (dy < -root.heightToggleDelta) {
            return "1x2"
        }
        if (dy > root.heightToggleDelta) {
            return newWidth >= root.wideThreshold ? "2x3" : "2x2"
        }

        if (newWidth >= root.wideThreshold) {
            return root.sizeMode === "1x2" ? "1x2" : "2x3"
        }
        return root.sizeMode === "1x2" ? "1x2" : "2x2"
    }

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Behavior on widgetWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on widgetHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // ── GPU Polling ──
    property real gpuUsage: 0
    property list<real> gpuHistory: []

    Process {
        id: gpuProc
        command: ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim())
                if (!isNaN(val)) {
                    root.gpuUsage = val
                    root.gpuHistory = [...root.gpuHistory, val / 100].slice(-60)
                }
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            gpuProc.running = false
            gpuProc.running = true
        }
    }

    // ── Ping Polling ──
    property real pingMs: 0

    Process {
        id: pingProc
        command: ["ping", "-c", "1", "-W", "1", "1.1.1.1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/(?:time|waktu)=([\d.]+)/i) || text.match(/rtt [^=]+=\s*[\d.]+\/([\d.]+)/)
                if (match) root.pingMs = parseFloat(match[1])
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pingProc.running = false
            pingProc.running = true
        }
    }

    // ── Physical LAN IP ──
    property string lanIp: "--"

    Process {
        id: lanIpProc
        command: ["bash", "-c", "ip -4 -o addr show scope global | grep -vE 'docker|warp|WARP|pan|tun|tap' | awk '{print $4}' | cut -d/ -f1 | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ip = text.trim()
                if (ip.length > 0) root.lanIp = ip
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            lanIpProc.running = false
            lanIpProc.running = true
        }
    }

    // ── Network Speed ──
    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property real prevRx: -1
    property real prevTx: -1
    property double prevTime: 0

    FileView {
        id: netStats
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.updateNetSpeed(text())
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: netStats.reload()
    }

    function updateNetSpeed(contents) {
        var rx = 0, tx = 0
        var lines = contents.split("\n")
        for (var line of lines) {
            var sep = line.indexOf(":")
            if (sep < 0) continue
            var iface = line.slice(0, sep).trim()
            if (!iface || iface === "lo" || iface.startsWith("docker") || iface.startsWith("pan") || iface.includes("warp") || iface.includes("WARP")) continue
            var fields = line.slice(sep + 1).trim().split(/\s+/)
            if (fields.length < 9) continue
            rx += Number(fields[0])
            tx += Number(fields[8])
        }
        var now = Date.now()
        if (prevTime > 0 && now > prevTime) {
            var elapsed = now - prevTime
            downloadSpeed = (rx >= prevRx ? rx - prevRx : 0) * 1000 / elapsed
            uploadSpeed = (tx >= prevTx ? tx - prevTx : 0) * 1000 / elapsed
        }
        prevRx = rx
        prevTx = tx
        prevTime = now
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec >= 1048576) return (bytesPerSec / 1048576).toFixed(1) + " MB/s"
        if (bytesPerSec >= 1024) return (bytesPerSec / 1024).toFixed(1) + " KB/s"
        return Math.round(bytesPerSec) + " B/s"
    }

    StyledRectangularShadow {
        target: card
        z: -2
        visible: Config.options.background.widgets.shadow
    }

    // ── Main Glass Card ──
    Rectangle {
        id: card
        implicitWidth: root.widgetWidth
        implicitHeight: root.widgetHeight
        width: root.widgetWidth
        height: root.widgetHeight
        radius: Appearance.rounding?.verylarge ?? 30
        color: Appearance.colors.colPrimaryContainer
        clip: true

        FastBlurred {
            anchors.fill: parent
            blurSource: root.wallpaperItem
            cardRadius: card.radius
            tint: Appearance.colors.colLayer1
            tintOpacity: 0.55
            trackX: root.x
            trackY: root.y
            visible: Config.options.background.widgets.blurWidgets && !GlobalStates.isLiveWallpaperRunning
        }

        Loader {
            anchors.fill: parent
            sourceComponent: {
                if (root.sizeMode === "1x1") return oneByOneContent
                if (root.sizeMode === "1x2") return oneByTwoContent
                if (root.sizeMode === "2x3") return twoByThreeContent
                return twoByTwoContent
            }
        }

        // ── Resize Handle ──
        ResizeHandler {
            anchorItem: card
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.widgetWidth
            resizeMode: "diagonal"
            onResizedXY: (dx, dy, startWidth) => {
                root.sizeMode = root.modeForDrag(dx, dy, startWidth)
            }
            onResizeFinished: {
                if (root.configEntry) {
                    root.configEntry.sizeMode = root.sizeMode
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // Component 1x1 (132 x 120)
    // ══════════════════════════════════════════════════════════
    Component {
        id: oneByOneContent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "monitoring"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "System"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.15
            }

            // CPU Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "CPU"
                    font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.6
                }

                StyledText {
                    text: Math.round((ResourceUsage?.cpuUsage ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                }

                Item { Layout.fillWidth: true }

                Sparkline {
                    implicitWidth: 46
                    implicitHeight: 18
                    dataPoints: ResourceUsage?.cpuUsageHistory ?? []
                    lineColor: "#38bdf8"
                }
            }

            // RAM Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "RAM"
                    font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.6
                }

                StyledText {
                    text: Math.round((ResourceUsage?.memoryUsedPercentage ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                }

                Item { Layout.fillWidth: true }

                Sparkline {
                    implicitWidth: 46
                    implicitHeight: 18
                    dataPoints: ResourceUsage?.memoryUsageHistory ?? []
                    lineColor: "#38bdf8"
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ══════════════════════════════════════════════════════════
    // Component 1x2 (276 x 120)
    // ══════════════════════════════════════════════════════════
    Component {
        id: oneByTwoContent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "monitoring"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "System / Network"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.15
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Left: CPU & RAM
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            text: "CPU " + Math.round((ResourceUsage?.cpuUsage ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        Item { Layout.fillWidth: true }
                        Sparkline {
                            implicitWidth: 46
                            implicitHeight: 16
                            dataPoints: ResourceUsage?.cpuUsageHistory ?? []
                            lineColor: "#38bdf8"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            text: "RAM " + Math.round((ResourceUsage?.memoryUsedPercentage ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        Item { Layout.fillWidth: true }
                        Sparkline {
                            implicitWidth: 46
                            implicitHeight: 16
                            dataPoints: ResourceUsage?.memoryUsageHistory ?? []
                            lineColor: "#38bdf8"
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.15
                }

                // Right: Download & Upload Speed
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "arrow_downward"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: root.formatSpeed(root.downloadSpeed)
                            font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "arrow_upward"
                            iconSize: 15
                            color: Appearance.colors.colTertiary
                        }
                        StyledText {
                            text: root.formatSpeed(root.uploadSpeed)
                            font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // Component 2x2 & 2x3 (Height 252)
    // ══════════════════════════════════════════════════════════
    Component {
        id: twoByTwoContent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "monitoring"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "System / Network"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            // Separator line
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.15
            }

            // Content: RowLayout
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Left Column (System)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 10

                    // CPU
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ColumnLayout {
                            spacing: 0
                            StyledText {
                                text: "CPU"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }
                            StyledText {
                                text: Math.round((ResourceUsage?.cpuUsage ?? 0) * 100) + "%"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Sparkline {
                            Layout.preferredWidth: root.sizeMode === "2x3" ? 110 : 64
                            Layout.preferredHeight: 28
                            dataPoints: ResourceUsage?.cpuUsageHistory ?? []
                            lineColor: "#38bdf8"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // GPU
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ColumnLayout {
                            spacing: 0
                            StyledText {
                                text: "GPU"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }
                            StyledText {
                                text: Math.round(root.gpuUsage) + "%"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Sparkline {
                            Layout.preferredWidth: root.sizeMode === "2x3" ? 110 : 64
                            Layout.preferredHeight: 28
                            dataPoints: root.gpuHistory
                            lineColor: "#38bdf8"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // RAM
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ColumnLayout {
                            spacing: 0
                            StyledText {
                                text: "RAM"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }
                            StyledText {
                                text: Math.round((ResourceUsage?.memoryUsedPercentage ?? 0) * 100) + "%"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Sparkline {
                            Layout.preferredWidth: root.sizeMode === "2x3" ? 110 : 64
                            Layout.preferredHeight: 28
                            dataPoints: ResourceUsage?.memoryUsageHistory ?? []
                            lineColor: "#38bdf8"
                        }
                    }
                }

                // Vertical separator
                Rectangle {
                    Layout.fillHeight: true
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    implicitWidth: 1
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.15
                }

                // Right Column (Network)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    // 1. Ping
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "wifi"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: "Ping"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.6
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: root.pingMs > 0 ? (Math.round(root.pingMs) + " ms") : "-- ms"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // 2. Download
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "arrow_downward"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: root.formatSpeed(root.downloadSpeed)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // 3. Upload
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "arrow_upward"
                            iconSize: 18
                            color: Appearance.colors.colTertiary
                        }

                        StyledText {
                            text: root.formatSpeed(root.uploadSpeed)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Separator before LAN
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.15
                    }

                    Item { Layout.fillHeight: true }

                    // 4. LAN
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "lan"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "LAN"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }

                            StyledText {
                                text: root.lanIp
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: twoByThreeContent
        Loader {
            sourceComponent: twoByTwoContent
        }
    }
}
