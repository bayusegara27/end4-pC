import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "discordVoice"
    hoverEnabled: true

    // ── Size grid (same system as Calendar / Weather) ──
    readonly property real cardSpacing: 12
    readonly property real singleWidth: 132
    readonly property real cardHeight: 120

    readonly property real snapWidth1: singleWidth
    readonly property real snapWidth2: singleWidth * 2 + cardSpacing
    readonly property real snapWidth3: singleWidth * 3 + cardSpacing * 2

    property string sizeMode: root.configEntry.sizeMode ?? "1x2"

    property real widgetWidth: {
        switch (root.sizeMode) {
            case "1x1": return snapWidth1
            case "1x2": return snapWidth2
            default:    return snapWidth3
        }
    }

    property int maxVisibleMembers: root.configEntry.maxVisibleMembers ?? 4

    function modeForWidth(value) {
        var mid1 = (snapWidth1 + snapWidth2) / 2
        var mid2 = (snapWidth2 + snapWidth3) / 2
        if (value < mid1) return "1x1"
        if (value < mid2) return "1x2"
        return "1x3"
    }

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Behavior on widgetWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // ── Data source ──
    property var voiceData: ({ channel: null, members: [] })

    FileView {
        id: voiceDataFileView
        path: "/tmp/discord_voice.json"
        watchChanges: true
        onFileChanged: voiceDataFileView.reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(voiceDataFileView.text().trim());
                root.voiceData = parsed;
            } catch(e) {}
        }
        onLoadFailed: {
            root.voiceData = { channel: null, members: [] };
        }
    }

    // ── Helpers ──
    readonly property var members: voiceData.members ?? []
    readonly property int memberCount: members.length
    readonly property string channelName: voiceData.channel ? voiceData.channel.name : ""
    readonly property bool inChannel: voiceData.channel !== null && voiceData.channel !== undefined

    property int visibleMemberCount: {
        if (sizeMode === "1x1") return 0
        var max = root.maxVisibleMembers
        if (sizeMode === "1x2") max = Math.min(max, 3)
        return Math.min(memberCount, max)
    }
    readonly property int overflowCount: Math.max(0, memberCount - visibleMemberCount)

    // ── Card ──
    Rectangle {
        id: card
        implicitWidth: root.widgetWidth
        implicitHeight: root.cardHeight
        radius: Appearance.rounding?.verylarge ?? 30
        color: Appearance.colors.colPrimaryContainer

        StyledRectangularShadow {
            target: card
            z: -2
        }

        Loader {
            anchors.fill: parent
            sourceComponent: {
                if (root.sizeMode === "1x1") return oneByOneContent
                if (root.sizeMode === "1x2") return oneByTwoContent
                return oneByThreeContent
            }
        }

        // ════════════════════════════════════════════
        // 1×1  — compact: icon + count + channel name
        // ════════════════════════════════════════════
        Component {
            id: oneByOneContent
            Item {
                anchors.fill: parent
                anchors.margins: 12

                MaterialShapeWrappedMaterialSymbol {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: root.inChannel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    colSymbol: Appearance.colors.colOnPrimary
                    text: root.inChannel ? "headset" : "headset_off"
                    iconSize: 20
                    fill: 1
                    padding: 8
                    implicitWidth: 36
                    implicitHeight: 36
                }

                StyledText {
                    id: countText
                    anchors.bottom: channelNameText.top
                    anchors.left: parent.left
                    anchors.bottomMargin: -2
                    text: root.inChannel ? root.memberCount + "" : "—"
                    font.pixelSize: 46
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    id: channelNameText
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.inChannel ? root.channelName : "Offline"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
        }

        // ════════════════════════════════════════════
        // 1×2  — medium: colored accent left + member list right
        // ════════════════════════════════════════════
        Component {
            id: oneByTwoContent
            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Left accent panel
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    radius: Appearance.rounding.verylarge ?? 30
                    color: root.inChannel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    // Fill right side gap
                    Rectangle {
                        width: parent.radius
                        height: parent.height
                        anchors.right: parent.right
                        color: parent.color
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 32
                            text: root.inChannel ? "headset" : "headset_off"
                            color: Appearance.colors.colOnPrimary
                            fill: 1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 80
                            text: root.inChannel ? root.channelName : "Offline"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                            opacity: 0.95
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.inChannel
                            text: root.memberCount + " member" + (root.memberCount !== 1 ? "s" : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimary
                            opacity: 0.75
                        }
                    }
                }

                // Right member list
                Item {
                    id: rightPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    property bool expanded: false

                    ListView {
                        id: memberListVertical
                        anchors {
                            fill: parent
                            margins: 10
                            leftMargin: 12
                        }
                        spacing: 4
                        clip: true
                        interactive: rightPanel.expanded

                        readonly property int maxCollapsed: 3

                        model: {
                            if (!root.inChannel) return 0
                            if (rightPanel.expanded) return root.memberCount + 1 // +1 for minimize button
                            if (root.memberCount > maxCollapsed) return maxCollapsed + 1 // 3 members + 1 badge
                            return root.memberCount
                        }

                        delegate: Item {
                            width: ListView.view.width
                            height: 22

                            readonly property bool isBadge: !rightPanel.expanded && root.memberCount > memberListVertical.maxCollapsed && index === memberListVertical.maxCollapsed
                            readonly property bool isMinimize: rightPanel.expanded && index === root.memberCount
                            readonly property var modelData: (!isBadge && !isMinimize && index < root.memberCount) ? root.members[index] : null

                            // 1. Regular Member
                            RowLayout {
                                anchors.fill: parent
                                spacing: 8
                                visible: !isBadge && !isMinimize

                                // Avatar
                                Image {
                                    source: modelData ? (modelData.avatar || "") : ""
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    Layout.alignment: Qt.AlignVCenter
                                    sourceSize: Qt.size(22, 22)
                                    fillMode: Image.PreserveAspectCrop

                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle { width: 22; height: 22; radius: 11 }
                                    }
                                }

                                StyledText {
                                    text: modelData ? (modelData.globalName || modelData.username) : ""
                                    color: Appearance.colors.colOnPrimaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Mute / deaf icons
                                RowLayout {
                                    spacing: 2
                                    MaterialSymbol {
                                        visible: modelData ? modelData.mute : false
                                        text: "mic_off"
                                        color: Appearance.colors.colError
                                        iconSize: 12
                                    }
                                    MaterialSymbol {
                                        visible: modelData ? modelData.deaf : false
                                        text: "headset_off"
                                        color: Appearance.colors.colError
                                        iconSize: 12
                                    }
                                }
                            }

                            // 2. "+X more" Badge
                            Item {
                                anchors.fill: parent
                                visible: isBadge
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 26
                                    height: 20
                                    width: badgeLayout.implicitWidth + 24
                                    radius: 10
                                    color: Appearance.colors.colLayer1
                                    
                                    RowLayout {
                                        id: badgeLayout
                                        anchors.centerIn: parent
                                        spacing: 4
                                        
                                        MaterialSymbol {
                                            text: "expand_more"
                                            color: Appearance.colors.colOnPrimaryContainer
                                            iconSize: 14
                                        }
                                        StyledText {
                                            text: "+" + (root.memberCount - memberListVertical.maxCollapsed) + " Show more"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rightPanel.expanded = true
                                }
                            }

                            // 3. "Minimize" Badge
                            Item {
                                anchors.fill: parent
                                visible: isMinimize
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 26
                                    height: 20
                                    width: minimizeLayout.implicitWidth + 24
                                    radius: 10
                                    color: Appearance.colors.colLayer1
                                    
                                    RowLayout {
                                        id: minimizeLayout
                                        anchors.centerIn: parent
                                        spacing: 4
                                        
                                        MaterialSymbol {
                                            text: "expand_less"
                                            color: Appearance.colors.colOnPrimaryContainer
                                            iconSize: 14
                                        }
                                        StyledText {
                                            text: "Show less"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        rightPanel.expanded = false
                                        memberListVertical.positionViewAtBeginning()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════════
        // 1×3  — full: header row + spacious member list
        // ════════════════════════════════════════════
        Component {
            id: oneByThreeContent
            ColumnLayout {
                id: cLayout
                property bool expanded: false
                anchors { fill: parent; margins: 12 }
                spacing: 6

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: root.inChannel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        colSymbol: Appearance.colors.colOnPrimary
                        text: root.inChannel ? "headset" : "headset_off"
                        iconSize: 18
                        fill: 1
                        padding: 6
                        implicitWidth: 32
                        implicitHeight: 32
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: root.inChannel ? root.channelName : "Not connected"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            visible: root.inChannel
                            text: root.memberCount + " member" + (root.memberCount !== 1 ? "s" : "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.6
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.3
                    visible: root.inChannel
                }

                // Member list
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    visible: root.inChannel

                    ListView {
                        id: memberList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        spacing: 12
                        clip: true
                        interactive: cLayout.expanded
                        
                        // Perfectly center items to fix right-side gap
                        readonly property real calculatedContentWidth: count * 44 + Math.max(0, count - 1) * spacing
                        leftMargin: cLayout.expanded ? 0 : Math.max(0, (width - calculatedContentWidth) / 2)
                        
                        // Calculate max displayable in collapsed mode
                        readonly property int maxCollapsed: 7
                        
                        model: {
                            if (!root.inChannel) return 0
                            if (cLayout.expanded) return root.memberCount + 1 // +1 for minimize button
                            if (root.memberCount > maxCollapsed) return maxCollapsed // 6 members + 1 badge
                            return root.memberCount
                        }
                        
                        delegate: Item {
                            height: ListView.view.height
                            width: 44
                            
                            readonly property bool isBadge: !cLayout.expanded && root.memberCount > memberList.maxCollapsed && index === (memberList.maxCollapsed - 1)
                            readonly property bool isMinimize: cLayout.expanded && index === root.memberCount
                            readonly property var modelData: (!isBadge && !isMinimize && index < root.memberCount) ? root.members[index] : null
                            
                            // 1. Regular Member
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                visible: !isBadge && !isMinimize

                                // Avatar
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32

                                    Image {
                                        anchors.fill: parent
                                        source: modelData ? (modelData.avatar || "") : ""
                                        sourceSize: Qt.size(32, 32)
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle { width: 32; height: 32; radius: 16 }
                                        }
                                    }

                                    // Mute/deaf badge
                                    Rectangle {
                                        visible: modelData ? (modelData.mute || modelData.deaf) : false
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: -2
                                        anchors.bottomMargin: -2
                                        width: 14; height: 14; radius: 7
                                        color: Appearance.colors.colError

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: modelData ? (modelData.deaf ? "headset_off" : "mic_off") : ""
                                            iconSize: 9
                                            color: Appearance.colors.colOnError
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 44
                                    text: modelData ? (modelData.globalName || modelData.username).split(" ")[0] : ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnPrimaryContainer
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            
                            // 2. "+X more" Badge
                            Item {
                                anchors.fill: parent
                                visible: isBadge
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 32; height: 32; radius: 16
                                        color: Appearance.colors.colLayer1
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "+" + (root.memberCount - (memberList.maxCollapsed - 1))
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: cLayout.expanded = true
                                        }
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "more"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnPrimaryContainer
                                        opacity: 0.5
                                    }
                                }
                            }
                            
                            // 3. "Minimize" Badge
                            Item {
                                anchors.fill: parent
                                visible: isMinimize
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 32; height: 32; radius: 16
                                        color: Appearance.colors.colLayer1
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close_fullscreen"
                                            iconSize: 16
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                cLayout.expanded = false
                                                memberList.positionViewAtBeginning()
                                            }
                                        }
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "less"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnPrimaryContainer
                                        opacity: 0.5
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Resize handle (same as Calendar / Weather) ──
        ResizeHandler {
            anchorItem: card
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.widgetWidth
            onResized: (newWidth) => { root.sizeMode = root.modeForWidth(newWidth) }
            onResizeFinished: { root.configEntry.sizeMode = root.sizeMode }
        }
    }
}
