import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Handles EasyEffects active state and presets.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false

    function fetchAvailability() {
        if (!fetchAvailabilityProc.running) {
            fetchAvailabilityProc.running = true
        }
    }

    function fetchActiveState() {
        if (!fetchActiveStateProc.running) {
            fetchActiveStateProc.running = true
        }
    }

    function disable() {
        root.active = false
        Quickshell.execDetached(["bash", "-c", "if pidof easyeffects >/dev/null 2>&1; then easyeffects -b 1; elif flatpak ps 2>/dev/null | grep -q com.github.wwmm.easyeffects; then flatpak run com.github.wwmm.easyeffects -b 1; fi"])
        syncTimer.restart()
    }

    function enable() {
        root.active = true
        Quickshell.execDetached(["bash", "-c", "if pidof easyeffects >/dev/null 2>&1; then easyeffects -b 2; elif flatpak ps 2>/dev/null | grep -q com.github.wwmm.easyeffects; then flatpak run com.github.wwmm.easyeffects -b 2; else easyeffects --hide-window --service-mode || flatpak run com.github.wwmm.easyeffects --hide-window --service-mode; fi"])
        syncTimer.restart()
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    Timer {
        id: syncTimer
        interval: 350
        repeat: false
        onTriggered: root.fetchActiveState()
    }

    Timer {
        running: (typeof GlobalStates !== "undefined" && GlobalStates?.sidebarRightOpen) ?? false
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.fetchAvailability()
            root.fetchActiveState()
        }
    }

    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v easyeffects || flatpak info com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
        }
    }

    Process {
        id: fetchActiveStateProc
        running: true
        command: ["bash", "-c", "if pidof easyeffects >/dev/null 2>&1; then [ \"$(easyeffects -b 3 2>/dev/null)\" = \"2\" ]; elif flatpak ps 2>/dev/null | grep -q com.github.wwmm.easyeffects; then [ \"$(flatpak run com.github.wwmm.easyeffects -b 3 2>/dev/null)\" = \"2\" ]; else false; fi"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
        }
    }
}
