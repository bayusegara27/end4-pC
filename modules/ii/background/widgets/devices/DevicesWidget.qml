import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "devices"
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

    // ── Session Connection Tracker ──
    property var sessionConnectedAddresses: ({})

    function recordConnection(key) {
        if (!key) return;
        if (!sessionConnectedAddresses[key]) {
            var copy = Object.assign({}, sessionConnectedAddresses);
            copy[key] = true;
            sessionConnectedAddresses = copy;
        }
    }

    // ── Telemetry & Bridge Data (/tmp/personal_telemetry.json) ──
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
        onTriggered: {
            telemetryFileView.reload();
            phoneReachableProc.running = true;
        }
    }

    Component.onCompleted: {
        telemetryFileView.reload();
        if (watchConnected) recordConnection("watch");
        if (phoneConnected) recordConnection("phone");
        if (headsetConnected) recordConnection("AZ09");
    }

    // ── Watch (Xiaomi Watch 2 Pro) ──
    readonly property var watchBluetoothDevice: {
        const list = Bluetooth.devices?.values ?? [];
        return list.find(d => d && (d.address === "B8:DE:5E:ED:BA:95" || (d.name && d.name.includes("Watch")))) ?? null;
    }
    readonly property bool watchConnected: Boolean(telemetryData?.synced) || (watchBluetoothDevice ? BluetoothStatus.isConnected(watchBluetoothDevice) : false)
    readonly property int watchBattery: (telemetryData && telemetryData.watch_battery != null && telemetryData.watch_battery > 0) ? telemetryData.watch_battery : -1
    readonly property string watchName: "Xiaomi Watch 2 Pro"

    onWatchConnectedChanged: {
        if (watchConnected) recordConnection("watch");
    }

    // ── Phone (Nakumi 14) ──
    readonly property string phoneDeviceId: "dea250a94e0d41fab16369613187e220"
    property bool kdePhoneConnected: false
    property int kdePhoneBattery: -1

    readonly property var phoneBluetoothDevice: {
        const list = Bluetooth.devices?.values ?? [];
        return list.find(d => d && (d.address === "E8:5F:B4:33:98:A6" || d.name === "Nakumi 14")) ?? null;
    }
    readonly property bool phoneConnected: Boolean(telemetryData?.phone_connected)
        || kdePhoneConnected
        || (phoneBluetoothDevice ? BluetoothStatus.isConnected(phoneBluetoothDevice) : false)

    readonly property int phoneBattery: {
        if (telemetryData && telemetryData.phone_battery != null && telemetryData.phone_battery > 0)
            return telemetryData.phone_battery;
        if (phoneBluetoothDevice && phoneBluetoothDevice.batteryAvailable && Number.isFinite(Number(phoneBluetoothDevice.battery))) {
            const b = Number(phoneBluetoothDevice.battery);
            return b <= 1 ? Math.round(b * 100) : Math.round(b);
        }
        if (kdePhoneBattery > 0) return kdePhoneBattery;
        return -1;
    }
    readonly property string phoneName: phoneBluetoothDevice?.name || telemetryData?.phone_name || "Nakumi 14"

    onPhoneConnectedChanged: {
        if (phoneConnected) recordConnection("phone");
    }

    Process {
        id: phoneReachableProc
        command: ["busctl", "--user", "get-property", "org.kde.kdeconnect",
                  "/modules/kdeconnect/devices/" + root.phoneDeviceId,
                  "org.kde.kdeconnect.device", "isReachable"]
        stdout: StdioCollector {
            onStreamFinished: {
                const reachable = text.trim().endsWith("true");
                root.kdePhoneConnected = reachable;
                if (reachable) {
                    phoneBatteryProc.running = true;
                }
            }
        }
    }

    Process {
        id: phoneBatteryProc
        command: ["busctl", "--user", "get-property", "org.kde.kdeconnect",
                  "/modules/kdeconnect/devices/" + root.phoneDeviceId,
                  "org.kde.kdeconnect.device.battery", "charge"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(text.trim().split(" ").pop());
                if (!isNaN(val) && val > 0) root.kdePhoneBattery = val;
            }
        }
    }

    // ── Headset (AZ09) ──
    readonly property var headsetDevice: {
        const list = Bluetooth.devices?.values ?? [];
        return list.find(d => d && (d.address === "00:00:00:00:3D:24" || (d.name && d.name.includes("AZ09")))) ?? null;
    }
    readonly property bool headsetConnected: Boolean(telemetryData?.headset_connected)
        || (headsetDevice ? BluetoothStatus.isConnected(headsetDevice) : false)

    readonly property int headsetBattery: {
        if (telemetryData && telemetryData.headset_battery != null && telemetryData.headset_battery > 0)
            return telemetryData.headset_battery;
        if (headsetDevice && headsetDevice.batteryAvailable && Number.isFinite(Number(headsetDevice.battery))) {
            const b = Number(headsetDevice.battery);
            return b <= 1 ? Math.round(b * 100) : Math.round(b);
        }
        return -1;
    }
    readonly property string headsetName: headsetDevice?.name || telemetryData?.headset_name || "AZ09"

    onHeadsetConnectedChanged: {
        if (headsetConnected) recordConnection("AZ09");
    }

    // ── Dynamic Active / Session Devices List ──
    readonly property var activeDevices: {
        var list = [];

        // 1. Smartwatch (Wear OS)
        if (root.watchConnected || root.sessionConnectedAddresses["watch"]) {
            list.push({
                id: "watch",
                icon: "watch",
                name: root.watchName,
                connected: root.watchConnected,
                battery: root.watchBattery
            });
        }

        // 2. Phone
        if (root.phoneConnected || root.sessionConnectedAddresses["phone"]) {
            list.push({
                id: "phone",
                icon: "smartphone",
                name: root.phoneName,
                connected: root.phoneConnected,
                battery: root.phoneBattery
            });
        }

        // 3. Headset (only if connected or connected this session)
        if (root.headsetConnected || root.sessionConnectedAddresses["AZ09"]) {
            list.push({
                id: "AZ09",
                icon: "headphones",
                name: root.headsetName,
                connected: root.headsetConnected,
                battery: root.headsetBattery
            });
        }

        // 4. Any other Bluetooth device that is currently connected
        const allBt = Bluetooth.devices?.values ?? [];
        for (var i = 0; i < allBt.length; i++) {
            var d = allBt[i];
            if (!d || !d.name) continue;
            if (d.address === "B8:DE:5E:ED:BA:95" || d.address === "E8:5F:B4:33:98:A6" || d.address === "00:00:00:00:3D:24") continue;
            var isConn = BluetoothStatus.isConnected(d);
            if (isConn) {
                root.recordConnection(d.address);
            }
            if (isConn || root.sessionConnectedAddresses[d.address]) {
                var bat = (d.batteryAvailable && Number.isFinite(Number(d.battery)))
                    ? Math.round(Number(d.battery) <= 1 ? d.battery * 100 : d.battery)
                    : -1;
                list.push({
                    id: d.address,
                    icon: Icons.getBluetoothDeviceMaterialSymbol(d.icon || ""),
                    name: d.name,
                    connected: isConn,
                    battery: bat
                });
            }
        }

        return list;
    }

    function getStatusText(connected, battery) {
        if (!connected) return Translation.tr("Disconnected");
        if (battery !== undefined && battery !== null && battery > 0) {
            return `${battery}%  ·  ${Translation.tr("Connected")}`;
        }
        return Translation.tr("Connected");
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
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "devices_other"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: Translation.tr("Devices")
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
                color: Appearance.colors.colOutlineVariant
                opacity: 0.25
            }

            Repeater {
                model: root.activeDevices.slice(0, 2)
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Appearance.rounding?.small ?? 8
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 16
                            color: modelData.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimaryContainer
                            opacity: modelData.connected ? 1.0 : 0.6
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.connected ? (modelData.battery > 0 ? `${modelData.battery}%` : Translation.tr("On")) : Translation.tr("Off")
                            font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: modelData.connected ? 0.9 : 0.5
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: modelData.connected ? "#4ade80" : Appearance.colors.colOutlineVariant
                            opacity: modelData.connected ? 1.0 : 0.4
                        }
                    }
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
                    text: "devices_other"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: Translation.tr("Devices")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.25
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Repeater {
                    model: root.activeDevices.slice(0, 2)
                    delegate: Rectangle {
                        id: compactTile
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding?.normal ?? 12
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: Appearance.rounding?.small ?? 8
                                color: compactTile.modelData.connected ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                                Layout.alignment: Qt.AlignVCenter

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: compactTile.modelData.icon
                                    iconSize: 18
                                    color: compactTile.modelData.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimaryContainer
                                    opacity: compactTile.modelData.connected ? 1.0 : 0.6
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: compactTile.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnPrimaryContainer
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: compactTile.modelData.connected ? (compactTile.modelData.battery > 0 ? `${compactTile.modelData.battery}%` : Translation.tr("Connected")) : Translation.tr("Disconnected")
                                    font.pixelSize: Appearance.font.pixelSize.smallest ?? 10
                                    color: Appearance.colors.colOnPrimaryContainer
                                    opacity: compactTile.modelData.connected ? 0.75 : 0.45
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: compactTile.modelData.connected ? "#4ade80" : Appearance.colors.colOutlineVariant
                                opacity: compactTile.modelData.connected ? 1.0 : 0.4
                            }
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "devices_other"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Devices")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.3
            }

            Repeater {
                model: root.activeDevices
                delegate: Rectangle {
                    id: devTile
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: Appearance.rounding?.normal ?? 14
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: Appearance.rounding?.small ?? 10
                            color: devTile.modelData.connected ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                            Layout.alignment: Qt.AlignVCenter

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: devTile.modelData.icon
                                iconSize: 22
                                color: devTile.modelData.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimaryContainer
                                opacity: devTile.modelData.connected ? 1.0 : 0.6
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: devTile.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.getStatusText(devTile.modelData.connected, devTile.modelData.battery)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: devTile.modelData.connected ? 0.75 : 0.45
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: devTile.modelData.connected ? "#4ade80" : Appearance.colors.colOutlineVariant
                            opacity: devTile.modelData.connected ? 1.0 : 0.4
                        }
                    }
                }
            }

            StyledText {
                visible: root.activeDevices.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 16
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("No active devices")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                opacity: 0.6
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: twoByThreeContent
        Loader {
            sourceComponent: twoByTwoContent
        }
    }
}
