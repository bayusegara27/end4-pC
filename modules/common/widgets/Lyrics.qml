pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common.functions

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    implicitWidth: 200
    implicitHeight: 200
    
    function restartLyrics() {
        LyricsService.restartLyrics()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status !== "ok"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48

                    MaterialLoadingIndicator {
                        anchors.fill: parent
                        loading: LyricsService.status === "loading"
                        colBg: root.indicatorColor
                        colShape: root.indicatorShapeColor
                        implicitSize: 48
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LyricsService.restartLyrics()
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.dimColor
                    text: {
                        if (LyricsService.status === "loading") return "Searching lyrics..."
                        if (LyricsService.status === "not_found") return "No lyrics found • Click to retry"
                        return "No song playing"
                    }
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            clip: true
            spacing: 10
            model: LyricsService.lyricsLines
            currentIndex: LyricsService.activeIndex
            
            preferredHighlightBegin: height * 0.35
            preferredHighlightEnd: height * 0.55
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 400
            
            delegate: StyledText {
                required property int index
                required property var modelData
                
                width: ListView.view.width
                horizontalAlignment: root.textAlignment
                wrapMode: Text.WordWrap
                text: modelData.text || "♪"
                
                readonly property int dist: Math.abs(index - ListView.view.currentIndex)
                
                property real targetSize: {
                    if (dist === 0) return Appearance.font.pixelSize.large * 1.05
                    if (dist === 1) return Appearance.font.pixelSize.normal
                    return Appearance.font.pixelSize.small
                }
                Behavior on targetSize { NumberAnimation { duration: 500; easing.type: Easing.OutQuart } }
                font.pixelSize: targetSize
                font.weight: dist === 0 ? Font.Bold : Font.DemiBold
                
                opacity: {
                    if (dist === 0) return 1.0
                    if (dist === 1) return 0.5
                    if (dist === 2) return 0.25
                    return 0.1
                }
                color: dist === 0 ? root.activeColor : root.textColor
                
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutQuart } }
                Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.OutQuart } }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: LyricsService.status === "ok"
            spacing: 6

            Rectangle {
                id: providerTag
                implicitHeight: 20
                implicitWidth: providerRow.implicitWidth + 12
                radius: 10
                color: ColorUtils.transparentize(root.activeColor, 0.85)

                RowLayout {
                    id: providerRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        iconSize: 11
                        color: root.activeColor
                        text: "music_note"
                    }

                    StyledText {
                        text: LyricsService.providerName || "Synced"
                        font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                        color: root.textColor
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: LyricsService.cycleProvider()
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 2
                visible: LyricsService.synced

                RippleButton {
                    implicitWidth: 18
                    implicitHeight: 18
                    buttonRadius: 9
                    colBackground: ColorUtils.transparentize(root.textColor, 0.9)
                    contentItem: MaterialSymbol {
                        iconSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        color: root.textColor
                        text: "remove"
                    }
                    downAction: () => LyricsService.adjustTiming(-0.5)
                }

                StyledText {
                    text: (LyricsService.timingOffset > 0 ? "+" : "") + LyricsService.timingOffset.toFixed(1) + "s"
                    font.pixelSize: Appearance.font.pixelSize.smaller * 0.85
                    color: LyricsService.timingOffset !== 0.0 ? root.activeColor : root.dimColor
                    font.features: { "tnum": 1 }
                }

                RippleButton {
                    implicitWidth: 18
                    implicitHeight: 18
                    buttonRadius: 9
                    colBackground: ColorUtils.transparentize(root.textColor, 0.9)
                    contentItem: MaterialSymbol {
                        iconSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        color: root.textColor
                        text: "add"
                    }
                    downAction: () => LyricsService.adjustTiming(0.5)
                }
            }
        }
    }
}