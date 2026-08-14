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
            
            preferredHighlightBegin: height * 0.4
            preferredHighlightEnd: height * 0.6
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
                    if (dist === 0) return Appearance.font.pixelSize.large * 1.1
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
    }
}