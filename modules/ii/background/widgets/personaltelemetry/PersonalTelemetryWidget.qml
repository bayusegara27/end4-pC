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
    configEntryName: "personalTelemetry"
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

    // ── Data Source ──
    property var telemetryData: null

    FileView {
        id: telemetryFileView
        path: "/tmp/personal_telemetry.json"
        watchChanges: true
        onFileChanged: telemetryFileView.reload()
        onLoaded: {
            try {
                const raw = telemetryFileView.text().trim();
                if (raw.length > 0) {
                    root.telemetryData = JSON.parse(raw);
                } else {
                    root.telemetryData = null;
                }
            } catch (e) {
                root.telemetryData = null;
            }
        }
        onLoadFailed: {
            root.telemetryData = null;
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: telemetryFileView.reload()
    }

    Component.onCompleted: {
        telemetryFileView.reload();
    }

    // ── Displayed values ──
    readonly property var telemetry: root.telemetryData

    readonly property string hrText: (telemetry && telemetry.hr_bpm != null && telemetry.hr_bpm > 0) ? String(telemetry.hr_bpm) : "--"
    readonly property string stepsText: {
        if (telemetry && telemetry.steps != null && Number(telemetry.steps) >= 0) {
            const num = Number(telemetry.steps);
            return isNaN(num) ? "--" : num.toLocaleString("en-US");
        }
        return "--";
    }
    readonly property string sleepText: {
        if (telemetry && (telemetry.sleep_hours != null || telemetry.sleep_minutes != null)) {
            const h = Number(telemetry.sleep_hours ?? 0);
            const m = Number(telemetry.sleep_minutes ?? 0);
            return `${h}h ${m}m`;
        }
        return "--";
    }
    readonly property string spo2Text: (telemetry && telemetry.spo2 != null && telemetry.spo2 > 0) ? `${telemetry.spo2}%` : "--"
    readonly property string tempText: (telemetry && telemetry.temp_c != null && telemetry.temp_c > 0) ? `${Number(telemetry.temp_c).toFixed(1)}°C` : "--"
    readonly property string watchBatteryText: (telemetry && telemetry.watch_battery != null && telemetry.watch_battery > 0) ? `${telemetry.watch_battery}%` : "--"
    readonly property bool isSynced: Boolean(telemetry?.synced)
    readonly property string syncStatusText: {
        if (root.isSynced) {
            const timeStr = telemetry?.sync_time;
            return timeStr ? `SYNCED · ${timeStr}` : "SYNCED";
        }
        return "OFFLINE";
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
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "vital_signs"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "Telemetry"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    elide: Text.ElideRight
                    Layout.fillWidth: true
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
                spacing: 6

                MaterialSymbol {
                    text: "favorite"
                    iconSize: 15
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: root.hrText + " bpm"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "footprint"
                    iconSize: 15
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.8
                }

                StyledText {
                    text: root.stepsText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                MaterialSymbol {
                    text: "sync"
                    iconSize: 11
                    color: root.isSynced ? "#4ade80" : Appearance.colors.colOutlineVariant
                }

                StyledText {
                    text: root.syncStatusText
                    font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: root.isSynced ? 0.8 : 0.5
                }
            }
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
                    text: "vital_signs"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "Personal Telemetry"
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
                spacing: 6

                // HR
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "favorite"
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.hrText
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "bpm"
                        font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 32
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.25
                }

                // Steps
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "footprint"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.stepsText
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "steps"
                        font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 32
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.25
                }

                // Watch Battery
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "watch"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.watchBatteryText
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "watch"
                        font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
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
                    text: "vital_signs"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: "Personal Telemetry"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            // Separator Line
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.15
            }

            // Top Stats Row
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Column 1: HR
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "favorite"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.hrText
                        font.pixelSize: 21
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "bpm"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                }

                // Vertical separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 44
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.15
                }

                // Column 2: Steps
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "footprint"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.stepsText
                        font.pixelSize: 21
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "steps"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                }

                // Vertical separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 44
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.15
                }

                // Column 3: Sleep
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "bedtime"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.sleepText
                        font.pixelSize: 21
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "sleep"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                }
            }

            // Middle Separator Line
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.3
            }

            // Bottom Stats Row (Clean icons and labels, NO border boxes)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // Column 1: SpO₂
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 36

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "water_drop"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: "SpO₂"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }

                            StyledText {
                                text: root.spo2Text
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }

                // Vertical separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 28
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.3
                }

                // Column 2: Temperature
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 36

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "thermometer"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: "Temp"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }

                            StyledText {
                                text: root.tempText
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }

                // Vertical separator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 28
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.3
                }

                // Column 3: Watch Battery
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 36

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "watch"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: "Watch"
                                font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.6
                            }

                            StyledText {
                                text: root.watchBatteryText
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }
                }
            }

            // Footer Row (Single sync time)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: 6

                MaterialSymbol {
                    text: "sync"
                    iconSize: Appearance.font.pixelSize.smaller ?? 12
                    color: root.isSynced ? "#4ade80" : Appearance.colors.colOutlineVariant
                }

                StyledText {
                    text: root.syncStatusText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: root.isSynced ? 0.75 : 0.5
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
