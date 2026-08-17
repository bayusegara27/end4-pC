import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * Modern notification card / group (Clean Material 3 & macOS glass aesthetic)
 */
MouseArea {
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real padding: 12

    implicitHeight: background.implicitHeight
    height: implicitHeight

    readonly property bool isCritical: notifications.some(n => n.urgency === NotificationUrgency.Critical.toString() || n.urgency === "2")

    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        if (root.qmlParent && root.qmlParent.resetDrag) root.qmlParent.resetDrag();
        background.anchors.leftMargin = background.anchors.leftMargin;
        destroyAnimation.left = left;
        destroyAnimation.discardFromHistory = true;
        destroyAnimation.running = true;
    }

    function dismissPopupWithAnimation(left = false) {
        if (root.qmlParent && root.qmlParent.resetDrag) root.qmlParent.resetDrag();
        background.anchors.leftMargin = background.anchors.leftMargin;
        destroyAnimation.left = left;
        destroyAnimation.discardFromHistory = false;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) {
            root.notifications.forEach(notif => {
                Notifications.cancelTimeout(notif.notificationId);
            });
        } else {
            root.notifications.forEach(notif => {
                Notifications.resumeTimeout(notif.notificationId);
            });
        }
    }

    SequentialAnimation {
        id: destroyAnimation
        property bool left: true
        property bool discardFromHistory: false
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    if (destroyAnimation.discardFromHistory || !root.popup) {
                        Notifications.discardNotification(notif.notificationId);
                    } else {
                        Notifications.timeoutNotification(notif.notificationId);
                    }
                });
            });
        }
    }

    function toggleExpanded() {
        root.expanded = !root.expanded;
    }

    DragManager {
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: {
            if (mouse.button === Qt.RightButton) 
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                if (root.popup) root.dismissPopupWithAnimation();
                else root.destroyWithAnimation();
            }
        }

        onDraggingChanged: () => {
            if (dragging && root.qmlParent) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            if (root.qmlParent) root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold) {
                if (root.popup) {
                    root.dismissPopupWithAnimation(diffX < 0);
                } else {
                    root.destroyWithAnimation(diffX < 0);
                }
            } else {
                dragManager.resetDrag();
            }
        }
    }

    StyledRectangularShadow {
        target: background
        visible: popup
    }

    Rectangle {
        id: background
        anchors.left: parent.left
        width: parent.width
        color: root.isCritical ? 
            ColorUtils.transparentize(Appearance.colors.colPrimary, 0.94) : 
            (popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2)
        radius: Appearance.rounding.normal
        clip: true
        anchors.leftMargin: root.xOffset

        border.width: root.isCritical ? 1.5 : 1
        border.color: root.isCritical ? 
            Appearance.colors.colPrimary : 
            ColorUtils.transparentize(Appearance.colors.colOutline, 0.75)

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        implicitHeight: mainLayout.implicitHeight + root.padding * 2
        height: implicitHeight

        ColumnLayout {
            id: mainLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padding
            spacing: 8

            // 1. Unified Card Header (Always shown)
            RowLayout {
                id: cardHeader
                Layout.fillWidth: true
                implicitHeight: 24
                spacing: 8

                NotificationAppIcon {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 24
                    implicitHeight: 24
                    appIcon: root.notificationGroup?.appIcon || ""
                    appName: root.notificationGroup?.appName || ""
                    summary: root.notificationGroup?.notifications[0]?.summary || ""
                    urgency: root.isCritical ? NotificationUrgency.Critical : NotificationUrgency.Normal
                }

                StyledText {
                    id: headerAppName
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.notificationGroup?.appName || Translation.tr("Notification")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.isCritical ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                // Critical status badge (seamless pill in header)
                Rectangle {
                    visible: root.isCritical
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    implicitHeight: 18
                    implicitWidth: critContent.implicitWidth + 10
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)

                    RowLayout {
                        id: critContent
                        anchors.centerIn: parent
                        spacing: 3
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "warning"
                            iconSize: 11
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Critical")
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "•"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    id: headerTime
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                    text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                // Mini Hover/Toast Status Indicator Pill (embedded in header)
                Rectangle {
                    visible: root.popup && !root.expanded
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    implicitHeight: 18
                    implicitWidth: timerContent.implicitWidth + 10
                    color: root.containsMouse ? 
                        ColorUtils.transparentize(Appearance.colors.colSecondary, 0.8) : 
                        ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)

                    RowLayout {
                        id: timerContent
                        anchors.centerIn: parent
                        spacing: 3

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.containsMouse ? "pause" : "schedule"
                            iconSize: 10
                            color: root.containsMouse ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.containsMouse ? Translation.tr("Hold") : Translation.tr("Auto")
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: root.containsMouse ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                        }
                    }
                }

                Item { 
                    Layout.fillWidth: true 
                    Layout.alignment: Qt.AlignVCenter
                }

                // Expand Chevron Pill (Precision 24px height, dead-centered)
                Rectangle {
                    id: expandPill
                    visible: root.multipleNotifications
                    Layout.alignment: Qt.AlignVCenter
                    height: 24
                    width: expandRow.implicitWidth + 14
                    radius: 12
                    color: expandMouse.containsMouse ? 
                        (expandMouse.pressed ? Appearance.colors.colLayer3Active : Appearance.colors.colLayer3Hover) : 
                        Appearance.colors.colLayer3

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    RowLayout {
                        id: expandRow
                        anchors.centerIn: parent
                        spacing: 3

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.notificationCount
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.expanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        id: expandMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.toggleExpanded();
                        }
                    }
                }

                // Header Dismiss / Close Button (Precision 24x24 circular, dead-centered, discards permanently)
                Rectangle {
                    id: closeButton
                    Layout.alignment: Qt.AlignVCenter
                    width: 24
                    height: 24
                    radius: 12
                    color: closeMouse.containsMouse ? 
                        (closeMouse.pressed ? Appearance.colors.colLayer3Active : Appearance.colors.colLayer3Hover) : 
                        Appearance.colors.colLayer3

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 13
                        color: Appearance.colors.colSubtext
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.destroyWithAnimation();
                        }
                    }
                }
            }

            // 2. Notification Items View (Repeater directly inside ColumnLayout for 100% synchronous height)
            Repeater {
                model: ScriptModel {
                    values: {
                        if (!root.notifications || root.notifications.length === 0) return [];
                        if (root.expanded) return root.notifications.slice().reverse();
                        return [root.notifications[root.notifications.length - 1]];
                    }
                }

                delegate: NotificationItem {
                    required property int index
                    required property var modelData
                    notificationObject: modelData
                    expanded: root.expanded
                    onlyNotification: (root.notificationCount === 1)
                    Layout.fillWidth: true
                }
            }
        }
    }
}
