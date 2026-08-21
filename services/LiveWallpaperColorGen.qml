pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Regenerates the palette when linux-wallpaperengine changes wallpaper.
 *
 * wpe-manager exposes no post-change hook, so its engine.json is watched
 * instead: that is the concrete "what is running on each screen" state, and it
 * is rewritten on every switch and on every playlist rotation. The work itself
 * lives in scripts/colors/wpe-colorsync.sh so it can also be run by hand.
 *
 * Does nothing when no live wallpaper is running — the script resolves that.
 */
Singleton {
    id: root

    // Singletons are instantiated lazily; shell.qml calls this to load it.
    function load() {}

    function sync(extraArgs) {
        Quickshell.execDetached(["bash", Directories.liveWallpaperColorSyncScriptPath]
            .concat(extraArgs ?? []))
    }

    Timer {
        id: settleTimer
        // wpe-manager overlaps the outgoing and incoming wallpaper and touches
        // engine.json more than once per switch; coalesce that into one run.
        interval: 1000
        repeat: false
        onTriggered: root.sync()
    }

    Timer {
        // At session start the backend is usually not up yet, so let the script
        // wait for it instead of resolving nothing.
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            // Bring the background in line with the chosen provider first: this
            // is what starts wpe-manager at login, since nothing on this setup
            // processes XDG autostart entries.
            Quickshell.execDetached(["bash", Directories.wallpaperProviderScriptPath, "apply"]);
            if (Config.options.background.provider !== "shell")
                root.sync(["--wait"]);
        }
    }

    FileView {
        path: Directories.wpeEnginePath
        watchChanges: true
        onFileChanged: settleTimer.restart()
        // wpe-manager may not be installed at all — that is not an error here.
        onLoadFailed: error => {}
    }
}
