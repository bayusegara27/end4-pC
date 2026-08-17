import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications

ColumnLayout { // Notification item (Direct ColumnLayout for exact synchronous layout calculations)
    id: root
    property var notificationObject
    property bool expanded: false
    property bool onlyNotification: false
    property real fontSize: Appearance.font.pixelSize.small

    Layout.fillWidth: true
    spacing: 6

    readonly property string detectedRawPath: NotificationUtils.extractFilePath((notificationObject?.body || "") + " " + (notificationObject?.summary || ""))
    readonly property string pathType: NotificationUtils.getPathType(root.detectedRawPath)
    readonly property string detectedUrl: NotificationUtils.extractUrl((notificationObject?.body || "") + " " + (notificationObject?.summary || ""))
    readonly property string detectedOtp: NotificationUtils.extractOtpCode((notificationObject?.summary || "") + " " + (notificationObject?.body || ""))
    readonly property bool isChat: NotificationUtils.isMessagingNotification(notificationObject?.appName, notificationObject?.summary, notificationObject?.body, notificationObject?.category)
    readonly property bool isDaemon: NotificationUtils.isSystemDaemon(notificationObject?.appName)
    readonly property bool hasProgress: notificationObject && notificationObject.progress !== undefined && notificationObject.progress >= 0
    readonly property bool isCritical: notificationObject && (notificationObject.urgency === NotificationUrgency.Critical.toString() || notificationObject.urgency === "2")
    readonly property bool hasBody: notificationObject && notificationObject.body && notificationObject.body.trim() !== ""
    readonly property bool hasSummary: notificationObject && notificationObject.summary && notificationObject.summary.trim() !== ""

    // Rich Media Preview (Screenshot, Image, or Video Thumbnail)
    readonly property string previewImagePath: {
        if (!notificationObject) return "";
        let img = notificationObject.image || "";
        if (img.startsWith("image://icon/")) {
            const raw = img.replace("image://icon/", "");
            if (raw.startsWith("/") || raw.startsWith("file://")) {
                img = raw;
            }
        }
        if (img.startsWith("file://") || img.startsWith("/") || img.endsWith(".png") || img.endsWith(".jpg") || img.endsWith(".jpeg") || img.endsWith(".webp")) {
            return img.startsWith("/") ? ("file://" + img) : img;
        }
        if (root.pathType === "image") {
            return "file://" + root.detectedRawPath;
        }
        return "";
    }
    readonly property bool hasImagePreview: previewImagePath !== ""

    readonly property bool isVideoMedia: root.pathType === "video"

    // Action visibility checker to collapse empty bottom row
    readonly property bool hasCustomActions: (notificationObject?.actions?.length || 0) > 0
    readonly property bool hasAnyAction: root.pathType !== "" || root.detectedUrl !== "" || root.detectedOtp !== "" || root.isChat || root.hasCustomActions || (!root.isDaemon && !root.hasImagePreview)

    // Native file / folder / app openers
    function openLocalFile(filePath) {
        if (!filePath || filePath === "") return;
        const clean = filePath.replace(/^file:\/\//, "");
        Quickshell.execDetached(["xdg-open", clean]);
    }

    function openFolder(filePath) {
        if (!filePath || filePath === "") return;
        const clean = filePath.replace(/^file:\/\//, "");
        if (root.pathType === "folder") {
            Quickshell.execDetached(["xdg-open", clean]);
            return;
        }
        const lastSlash = clean.lastIndexOf("/");
        const dir = lastSlash > 0 ? clean.substring(0, lastSlash) : clean;
        Quickshell.execDetached(["xdg-open", dir]);
    }

    function openUrl(url) {
        if (!url || url === "") return;
        if (url.startsWith("http://") || url.startsWith("https://")) {
            Qt.openUrlExternally(url);
        } else {
            openLocalFile(url);
        }
    }

    function openApp() {
        if (!notificationObject) return;
        if (!Notifications.invokeDefaultAction(notificationObject.notificationId)) {
            if (root.isVideoMedia || (root.pathType === "file" || root.pathType === "image")) {
                root.openLocalFile(root.detectedRawPath);
            } else if (!root.isDaemon) {
                NotificationUtils.focusOrLaunchApp(notificationObject.appName, notificationObject.desktopEntry);
            } else if (root.pathType === "folder" || root.detectedRawPath !== "") {
                root.openFolder(root.detectedRawPath);
            }
        }
    }

    function handleSendReply(text) {
        if (!text || text.trim().length === 0) return;
        if (notificationObject?.hasInlineReply) {
            Notifications.sendInlineReply(notificationObject.notificationId, text);
        }
    }

    // Subtle divider between items when expanded in a bundle
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 4
        Layout.preferredHeight: 1
        visible: !root.onlyNotification && root.expanded && index > 0
        color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.8)
    }

    // Title / Summary (Clickable to activate default action or focus app)
    StyledText {
        id: summaryText
        visible: root.hasSummary
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.DemiBold
        color: root.isCritical ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        elide: Text.ElideRight
        maximumLineCount: root.expanded ? 3 : 1
        wrapMode: Text.Wrap
        text: root.notificationObject?.summary || ""

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openApp()
        }
    }

    // Body message text
    StyledText {
        id: bodyText
        visible: root.hasBody
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
        lineHeight: 1.2
        maximumLineCount: root.expanded ? 8 : 2
        elide: Text.ElideRight
        textFormat: Text.RichText
        text: {
            if (!notificationObject) return "";
            return NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>");
        }

        onLinkActivated: (link) => {
            root.openUrl(link);
            GlobalStates.sidebarRightOpen = false;
        }
        
        PointingHandLinkHover {}
    }

    // Rich Media Preview Card (Screenshot, Image, or Video Thumbnail)
    Rectangle {
        id: imagePreviewContainer
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 2
        Layout.preferredHeight: root.hasImagePreview ? 130 : 0
        Layout.minimumHeight: root.hasImagePreview ? 130 : 0
        visible: root.hasImagePreview
        radius: 10
        color: Appearance.colors.colLayer3
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.75)
        clip: true

        Image {
            id: previewImg
            anchors.fill: parent
            anchors.margins: 1
            source: root.previewImagePath
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: false
            clip: true
        }

        // Interactive hover overlay (Click to open image or play video)
        MouseArea {
            id: imageClickArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (root.isVideoMedia && root.detectedRawPath !== "") {
                    root.openLocalFile(root.detectedRawPath);
                } else {
                    root.openLocalFile(root.previewImagePath);
                }
            }

            // Video Play Badge in center when it's a video thumbnail
            Rectangle {
                anchors.centerIn: parent
                visible: root.isVideoMedia && !imageClickArea.containsMouse
                width: 40
                height: 40
                radius: 20
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)

                MaterialSymbol {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1
                    text: "play_arrow"
                    iconSize: 22
                    color: Appearance.colors.colOnPrimary
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 9
                color: imageClickArea.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.5) : "transparent"
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                RowLayout {
                    anchors.centerIn: parent
                    visible: imageClickArea.containsMouse
                    spacing: 6

                    MaterialSymbol {
                        text: root.isVideoMedia ? "play_circle" : "fullscreen"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: root.isVideoMedia ? Translation.tr("Putar Video") : Translation.tr("Lihat Gambar")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // Integrated Frosted Progress Module (for downloads & background tasks)
    Rectangle {
        id: progressContainer
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 2
        Layout.preferredHeight: root.hasProgress ? 46 : 0
        Layout.minimumHeight: root.hasProgress ? 46 : 0
        visible: root.hasProgress
        radius: 10
        color: ColorUtils.transparentize(Appearance.colors.colLayer3, 0.4)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.8)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    text: (notificationObject?.progress || 0) >= 100 ? "check_circle" : "downloading"
                    iconSize: 13
                    color: (notificationObject?.progress || 0) >= 100 ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                }
                StyledText {
                    text: (notificationObject?.progress || 0) >= 100 ? Translation.tr("Completed") : Translation.tr("Downloading")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                }
                StyledText {
                    text: (notificationObject?.progress || 0) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
            }

            // Smooth rounded pill progress track
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 5
                radius: 2.5
                color: Appearance.colors.colLayer4
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, (notificationObject?.progress || 0) / 100.0))
                    radius: 2.5
                    color: (notificationObject?.progress || 0) >= 100 ? Appearance.colors.colSecondary : Appearance.colors.colPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                        }
                    }
                }
            }
        }
    }

    // Native DBus Inline Reply Input (Shown ONLY if the application natively supports it)
    RowLayout {
        id: inlineReplyRow
        Layout.fillWidth: true
        Layout.topMargin: 3
        visible: (notificationObject?.hasInlineReply ?? false) && (root.expanded || root.onlyNotification)
        spacing: 6

        MaterialTextField {
            id: replyInput
            Layout.fillWidth: true
            placeholderText: Translation.tr("Ketik balasan...")
            onAccepted: {
                root.handleSendReply(text);
                text = "";
            }
        }

        NotificationActionButton {
            buttonIcon: "send"
            buttonText: Translation.tr("Kirim")
            isPrimary: true
            onClicked: {
                root.handleSendReply(replyInput.text);
                replyInput.text = "";
            }
        }
    }

    // Ultra-Clean, Contextual Action Row (Zero redundant buttons)
    RowLayout {
        id: unifiedActionRow
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: (root.expanded || root.onlyNotification) && root.hasAnyAction
        spacing: 6

        // 1. Folder Only (e.g. /home/nakumi/Video from Recorder)
        NotificationActionButton {
            visible: root.pathType === "folder"
            buttonIcon: "folder_open"
            buttonText: Translation.tr("Buka Folder")
            isPrimary: true
            onClicked: {
                root.openFolder(root.detectedRawPath);
            }
        }

        // 2. Video File (e.g. recording.mp4)
        NotificationActionButton {
            visible: root.isVideoMedia
            buttonIcon: "play_circle"
            buttonText: Translation.tr("Putar Video")
            isPrimary: true
            onClicked: {
                root.openLocalFile(root.detectedRawPath);
            }
        }

        // 3. Image / Screenshot
        NotificationActionButton {
            visible: (root.hasImagePreview && !root.isVideoMedia) || (root.pathType === "image")
            buttonIcon: "visibility"
            buttonText: Translation.tr("Lihat Gambar")
            isPrimary: true
            onClicked: {
                root.openLocalFile(root.previewImagePath !== "" ? root.previewImagePath : root.detectedRawPath);
            }
        }

        // 4. Document / Generic File
        NotificationActionButton {
            visible: (root.pathType === "file" || root.pathType === "audio") && !root.hasImagePreview && !root.isVideoMedia
            buttonIcon: "description"
            buttonText: Translation.tr("Buka Berkas")
            isPrimary: true
            onClicked: {
                root.openLocalFile(root.detectedRawPath);
            }
        }

        // Secondary Folder button (For video, images, or documents)
        NotificationActionButton {
            visible: root.isVideoMedia || root.pathType === "file" || root.pathType === "audio" || (root.hasImagePreview && root.pathType !== "")
            buttonIcon: "folder_open"
            buttonText: Translation.tr("Folder")
            onClicked: {
                root.openFolder(root.detectedRawPath !== "" ? root.detectedRawPath : root.previewImagePath);
            }
        }

        // 5. Web URL Link
        NotificationActionButton {
            visible: root.detectedUrl !== "" && root.pathType === ""
            buttonIcon: "language"
            buttonText: Translation.tr("Buka Link")
            isPrimary: true
            onClicked: {
                root.openUrl(root.detectedUrl);
            }
        }

        // 6. OTP / Verification Code (Dedicated smart chip)
        NotificationActionButton {
            visible: root.detectedOtp !== ""
            buttonIcon: "key"
            buttonText: Translation.tr("Salin Kode: %1").arg(root.detectedOtp)
            isPrimary: true
            onClicked: {
                Quickshell.clipboardText = root.detectedOtp;
            }
        }

        // 7. Chat Conversation
        NotificationActionButton {
            visible: root.isChat && root.pathType === "" && root.detectedUrl === "" && root.detectedOtp === ""
            buttonIcon: "chat"
            buttonText: Translation.tr("Buka Chat")
            isPrimary: true
            onClicked: {
                root.openApp();
            }
        }

        // 8. Regular GUI Application (Only if not a daemon, and no file/url/chat actions)
        NotificationActionButton {
            visible: !root.isDaemon && !root.isChat && root.pathType === "" && root.detectedUrl === "" && root.detectedOtp === "" && !root.hasImagePreview && !root.hasCustomActions
            buttonIcon: "open_in_new"
            buttonText: Translation.tr("Buka App")
            isPrimary: true
            onClicked: {
                root.openApp();
            }
        }

        // App-registered Actions (e.g. media player controls, custom dialog actions)
        Repeater {
            id: actionRepeater
            model: notificationObject?.actions || []
            NotificationActionButton {
                id: notifAction
                required property var modelData
                required property int index
                visible: modelData && modelData.text && modelData.text.trim() !== ""
                buttonText: modelData?.text || ""
                urgency: notificationObject?.urgency || "normal"
                isPrimary: index === 0
                onClicked: {
                    Notifications.attemptInvokeAction(notificationObject.notificationId, modelData.identifier);
                }
            }
        }
    }
}
