import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

Item {
    id: root
    property var appIcon: ""
    property var summary: ""
    property var appName: ""
    property var category: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical.toString() || urgency === NotificationUrgency.Critical || urgency === "2"
    property var image: ""

    implicitWidth: 36
    implicitHeight: 36

    // Resolve whether icon or image is a valid existing path
    readonly property string resolvedIconPath: {
        if (!root.appIcon || root.appIcon === "") return "";
        // If it starts with file:// or absolute path
        if (root.appIcon.startsWith("file://") || root.appIcon.startsWith("/")) return root.appIcon;
        // Check if quickshell finds it in system theme
        const p = Quickshell.iconPath(root.appIcon);
        if (p && p !== "" && !p.includes("image-missing")) return p;
        return "";
    }

    readonly property bool hasValidImage: {
        if (!root.image || root.image === "") return false;
        if (root.image.startsWith("image://icon/") && root.image.includes("missing")) return false;
        return true;
    }

    readonly property bool hasValidIcon: root.resolvedIconPath !== ""

    // Container background circle
    Rectangle {
        id: bgCircle
        anchors.fill: parent
        radius: width / 2
        color: root.isUrgent ? 
            ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2) : 
            Appearance.colors.colLayer3
        border.width: 1
        border.color: root.isUrgent ? 
            Appearance.colors.colPrimary : 
            ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)

        // Case 1: Display Image if valid (e.g. contact avatar or custom image)
        Image {
            id: customImage
            visible: root.hasValidImage
            anchors.fill: parent
            anchors.margins: 1
            source: root.image
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: customImage.width
                    height: customImage.height
                    radius: width / 2
                }
            }
        }

        // Case 2: Display System IconImage if resolved successfully
        IconImage {
            id: systemIcon
            visible: !root.hasValidImage && root.hasValidIcon
            anchors.centerIn: parent
            implicitWidth: 22
            implicitHeight: 22
            asynchronous: true
            source: root.resolvedIconPath
        }

        // Case 3: Fallback to crisp Material Symbol (Prevents broken magenta checkerboard!)
        MaterialSymbol {
            id: fallbackMaterialIcon
            visible: !root.hasValidImage && !root.hasValidIcon
            anchors.centerIn: parent
            text: {
                if (root.isUrgent) return "warning";
                return NotificationUtils.findSuitableMaterialSymbol(root.summary, root.appName, root.category);
            }
            iconSize: 20
            color: root.isUrgent ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
        }
    }
}
