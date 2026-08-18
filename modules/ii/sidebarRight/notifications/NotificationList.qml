import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property string searchText: ""
    property string activeFilter: "all"
    property bool showDndMenu: false // "all", "critical", "downloads"

    // Helper functions for search & filter
    function matchesFilter(notif) {
        if (!notif) return false;
        
        // Filter by category / urgency
        if (root.activeFilter === "critical") {
            if (notif.urgency !== "critical" && notif.urgency !== "2") return false;
        } else if (root.activeFilter === "downloads") {
            if (notif.progress === undefined || notif.progress < 0) return false;
        }

        // Filter by search query
        if (root.searchText.trim() !== "") {
            const query = root.searchText.toLowerCase().trim();
            const app = (notif.appName || "").toLowerCase();
            const summary = (notif.summary || "").toLowerCase();
            const body = (notif.body || "").toLowerCase();
            return app.includes(query) || summary.includes(query) || body.includes(query);
        }

        return true;
    }

    readonly property var filteredNotifications: Notifications.list.filter(matchesFilter)

    function getFilteredGroups(list) {
        const groups = {};
        if (!list) return groups;
        list.forEach((notif) => {
            if (!notif) return;
            const app = notif.appName || "Other";
            if (!groups[app]) {
                groups[app] = {
                    appName: app,
                    appIcon: notif.appIcon || "",
                    notifications: [],
                    time: notif.time || Date.now()
                };
            }
            groups[app].notifications.push(notif);
            if (notif.time && notif.time > groups[app].time) {
                groups[app].time = notif.time;
            }
        });
        return groups;
    }

    readonly property var filteredGroups: getFilteredGroups(filteredNotifications)
    readonly property list<string> filteredAppNameList: Object.keys(filteredGroups).sort((a, b) => {
        const timeA = filteredGroups[a]?.time || 0;
        const timeB = filteredGroups[b]?.time || 0;
        return timeB - timeA;
    })

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Search & Filter Header (when there are notifications)
        ColumnLayout {
            Layout.fillWidth: true
            visible: Notifications.list.length > 0
            spacing: 8

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 18
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: searchField.activeFocus ? 
                    Appearance.colors.colPrimary : 
                    ColorUtils.transparentize(Appearance.colors.colOutline, 0.75)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }

                    StyledTextInput {
                        id: searchField
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        onTextChanged: {
                            root.searchText = text;
                        }

                        StyledText {
                            anchors.fill: parent
                            visible: searchField.text === "" && !searchField.activeFocus
                            text: Translation.tr("Search notifications...")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        visible: searchField.text !== ""
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: 11
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }

                        onClicked: {
                            searchField.text = "";
                            root.searchText = "";
                        }
                    }
                }
            }

            // Quick Filter Chips
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                RippleButton {
                    id: chipAll
                    property bool selected: root.activeFilter === "all"
                    implicitHeight: 28
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: 14
                    colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colRipple: selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("All (%1)").arg(Notifications.list.length)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: chipAll.selected ? Font.Bold : Font.Normal
                        color: chipAll.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }

                    onClicked: { root.activeFilter = "all"; }
                }

                RippleButton {
                    id: chipCritical
                    readonly property int critCount: Notifications.list.filter(n => n.urgency === "critical" || n.urgency === "2").length
                    visible: critCount > 0
                    property bool selected: root.activeFilter === "critical"
                    implicitHeight: 28
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: 14
                    colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colRipple: selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "warning"
                            iconSize: 14
                            color: chipCritical.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Critical (%1)").arg(chipCritical.critCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: chipCritical.selected ? Font.Bold : Font.Normal
                            color: chipCritical.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }

                    onClicked: { root.activeFilter = "critical"; }
                }

                RippleButton {
                    id: chipDownloads
                    readonly property int dlCount: Notifications.list.filter(n => n.progress !== undefined && n.progress >= 0).length
                    visible: dlCount > 0
                    property bool selected: root.activeFilter === "downloads"
                    implicitHeight: 28
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: 14
                    colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colRipple: selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "downloading"
                            iconSize: 14
                            color: chipDownloads.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondary
                        }
                        StyledText {
                            text: Translation.tr("Progress (%1)").arg(chipDownloads.dlCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: chipDownloads.selected ? Font.Bold : Font.Normal
                            color: chipDownloads.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }

                    onClicked: { root.activeFilter = "downloads"; }
                }
            }
        }

        // Notification List View
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            StyledListView {
                id: listview
                anchors.fill: parent
                clip: true
                spacing: 10
                animateMovement: true

                model: ScriptModel {
                    values: root.filteredAppNameList
                }

                delegate: NotificationGroup {
                    required property int index
                    required property var modelData
                    popup: false
                    width: ListView.view.width
                    notificationGroup: root.filteredGroups[modelData]
                }
            }

            // Placeholder when list is empty
            PagePlaceholder {
                shown: Notifications.list.length === 0
                icon: "notifications_active"
                description: Translation.tr("No notifications")
                shape: MaterialShape.Shape.Ghostish
                descriptionHorizontalAlignment: Text.AlignHCenter
            }

            // Placeholder when filter finds nothing
            PagePlaceholder {
                shown: Notifications.list.length > 0 && root.filteredNotifications.length === 0
                icon: "search_off"
                description: Translation.tr("No matching notifications")
                shape: MaterialShape.Shape.Circle
                descriptionHorizontalAlignment: Text.AlignHCenter
            }
        }

        // DND Timer Selector Row (Expandable)
        RowLayout {
            id: dndTimerRow
            Layout.fillWidth: true
            visible: root.showDndMenu
            spacing: 6

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: Notifications.dndMode === "manual" && Notifications.isDndActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                buttonText: Translation.tr("Always")
                downAction: () => {
                    Notifications.enableDnd(0);
                    root.showDndMenu = false;
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: Notifications.dndMode === "timed" && Notifications.dndRemainingMinutes <= 30 && Notifications.isDndActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                buttonText: Translation.tr("30m")
                downAction: () => {
                    Notifications.enableDnd(30);
                    root.showDndMenu = false;
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: Notifications.dndMode === "timed" && Notifications.dndRemainingMinutes > 30 && Notifications.dndRemainingMinutes <= 60 && Notifications.isDndActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                buttonText: Translation.tr("1h")
                downAction: () => {
                    Notifications.enableDnd(60);
                    root.showDndMenu = false;
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: Notifications.dndMode === "timed" && Notifications.dndRemainingMinutes > 60 && Notifications.isDndActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                buttonText: Translation.tr("2h")
                downAction: () => {
                    Notifications.enableDnd(120);
                    root.showDndMenu = false;
                }
            }

            RippleButton {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                downAction: () => {
                    root.showDndMenu = false;
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // Bottom Action Bar
        ButtonGroup {
            id: statusRow
            Layout.fillWidth: true

            NotificationStatusButton {
                Layout.fillWidth: false
                buttonIcon: Notifications.isDndActive ? "notifications_off" : "notifications"
                toggled: Notifications.isDndActive
                onClicked: () => {
                    if (Notifications.isDndActive) {
                        Notifications.disableDnd();
                        root.showDndMenu = false;
                    } else {
                        Notifications.enableDnd(0);
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            root.showDndMenu = !root.showDndMenu;
                        }
                    }
                }

                StyledToolTip {
                    text: {
                        if (!Notifications.isDndActive) return Translation.tr("Do Not Disturb: OFF (Left-click: toggle, Right-click: timer presets)");
                        if (Notifications.dndMode === "timed" && Notifications.dndRemainingMinutes > 0) {
                            return Translation.tr("Do Not Disturb: ON (%1m remaining)").arg(Notifications.dndRemainingMinutes);
                        }
                        if (Notifications.isFullscreenActive) {
                            return Translation.tr("Do Not Disturb: ON (Auto - Fullscreen App/Game)");
                        }
                        if (Notifications.isScheduleActive) {
                            return Translation.tr("Do Not Disturb: ON (Scheduled Quiet Hours)");
                        }
                        return Translation.tr("Do Not Disturb: ON (Persistent/Always - Right-click for timers)");
                    }
                }
            }

            NotificationStatusButton {
                enabled: true
                Layout.fillWidth: true
                buttonText: {
                    if (Notifications.isDndActive && Notifications.dndMode === "timed" && Notifications.dndRemainingMinutes > 0) {
                        return Translation.tr("DND: %1m | %2 notifs").arg(Notifications.dndRemainingMinutes).arg(Notifications.list.length);
                    }
                    return Translation.tr("%1 notifications").arg(Notifications.list.length);
                }
                onClicked: () => {
                    root.showDndMenu = !root.showDndMenu;
                }
                StyledToolTip {
                    text: Translation.tr("Click to toggle DND duration presets")
                }
            }

            NotificationStatusButton {
                Layout.fillWidth: false
                buttonIcon: "delete_sweep"
                enabled: Notifications.list.length > 0
                onClicked: () => {
                    Notifications.discardAllNotifications();
                }
                StyledToolTip {
                    text: Translation.tr("Clear all notifications")
                }
            }
        }
    }
}
