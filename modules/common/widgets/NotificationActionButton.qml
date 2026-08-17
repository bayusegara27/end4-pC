import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string buttonText: ""
    property string urgency: "normal"
    property string buttonIcon: ""
    property bool isPrimary: false

    readonly property bool isCritical: urgency === NotificationUrgency.Critical.toString() || urgency === "2"

    // Hide button if it has neither icon nor text (prevents empty pill glitch)
    visible: buttonText.trim() !== "" || buttonIcon !== ""

    implicitHeight: 28
    leftPadding: buttonIcon !== "" && buttonText === "" ? 7 : 10
    rightPadding: buttonIcon !== "" && buttonText === "" ? 7 : 10
    buttonRadius: 14
    
    colBackground: isCritical ? 
        (isPrimary ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer) : 
        (isPrimary ? Appearance.colors.colPrimary : Appearance.colors.colLayer3)
        
    colBackgroundHover: isCritical ? 
        (isPrimary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover) : 
        (isPrimary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover)
        
    colRipple: isCritical ? 
        (isPrimary ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive) : 
        (isPrimary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active)

    contentItem: RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        MaterialSymbol {
            id: icon
            visible: button.buttonIcon !== ""
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: button.buttonIcon
            iconSize: 14
            color: button.isPrimary ? Appearance.colors.colOnPrimary : 
                (button.isCritical ? Appearance.m3colors.m3onSurfaceVariant : Appearance.colors.colOnLayer2)
        }

        StyledText {
            id: textLabel
            visible: button.buttonText !== ""
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: button.buttonText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: button.isPrimary ? Font.DemiBold : Font.Normal
            color: button.isPrimary ? Appearance.colors.colOnPrimary : 
                (button.isCritical ? Appearance.m3colors.m3onSurfaceVariant : Appearance.colors.colOnLayer2)
        }
    }
}
