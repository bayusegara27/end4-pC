pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "loading"
    property var slots: ["", "", "", "", "", "", ""]
    property string providerName: ""
    property string preferredProvider: Config.options?.bar?.media?.lyricsProvider || "auto"
    property real timingOffset: 0.0

    readonly property var providerList: [
        { id: "auto", name: "Automatic" },
        { id: "lrclib", name: "LRCLIB" },
        { id: "netease", name: "Netease Cloud Music" },
        { id: "kugou", name: "Kugou" },
        { id: "qqmusic", name: "QQ Music" },
        { id: "ytmusic", name: "YouTube Music" }
    ]

    function cycleProvider() {
        let idx = 0
        for (let i = 0; i < root.providerList.length; i++) {
            if (root.providerList[i].id === root.preferredProvider) {
                idx = (i + 1) % root.providerList.length
                break
            }
        }
        root.preferredProvider = root.providerList[idx].id
        if (Config.options?.bar?.media) {
            Config.options.bar.media.lyricsProvider = root.preferredProvider
        }
        root.restartLyrics(root.preferredProvider)
    }

    function adjustTiming(delta) {
        root.timingOffset = Math.round((root.timingOffset + delta) * 10) / 10
        root.update()
    }

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    readonly property bool playing: root.activePlayer?.isPlaying ?? false
    readonly property bool synced: root.status === "ok" && root.lyricsLines.length > 0
    readonly property real leadSeconds: 0.15

    property real basePosition: 0
    property real baseTime: Date.now()

    function currentPosition() {
        const base = root.playing ? root.basePosition + (Date.now() - root.baseTime) / 1000 : root.basePosition
        return base + root.timingOffset
    }

    function resync() {
        if (!root.activePlayer) return
        root.activePlayer.positionChanged()
        readPositionTimer.restart()
    }

    function indexAt(pos) {
        const lines = root.lyricsLines
        let low = 0
        let high = lines.length - 1
        let result = -1
        while (low <= high) {
            const mid = (low + high) >> 1
            if (lines[mid].time <= pos) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    function update() {
        boundaryTimer.stop()
        if (!root.synced) return
        const idx = root.indexAt(root.currentPosition() + root.leadSeconds)
        if (idx !== root.activeIndex) {
            root.activeIndex = idx
            root.slots = root.buildSlots(idx)
        }
        const next = root.lyricsLines[idx + 1]
        if (!root.playing || !next) return
        const delay = (next.time - root.leadSeconds - root.currentPosition()) * 1000
        boundaryTimer.interval = Math.max(1, Math.ceil(delay))
        boundaryTimer.start()
    }

    Timer {
        id: readPositionTimer
        interval: 80
        onTriggered: {
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            root.update()
        }
    }

    Timer {
        id: boundaryTimer
        onTriggered: root.update()
    }

    Timer {
        id: driftTimer
        interval: 4000
        repeat: true
        running: root.synced && root.playing
        onTriggered: root.resync()
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                console.log("LYRICS DEBUG READ:", trimmed.substring(0, 100) + "... LENGTH:", trimmed.length)
                if (trimmed === "not_found") { 
                    root.status = "not_found"
                    root.providerName = ""
                    return 
                }
                if (trimmed === "no_info") { 
                    root.status = "no_info"
                    root.providerName = ""
                    return 
                }

                const parts = trimmed.split("§")
                if (parts.length < 3) {
                    console.log("LYRICS DEBUG: parts length < 3")
                    return
                }
                if (parts[parts.length - 1].trim() !== "ok") {
                    console.log("LYRICS DEBUG: not ok ending! It ends with:", parts[parts.length - 1])
                    return
                }

                let lines = []
                let prov = ""
                for (let i = 0; i < parts.length - 1; i += 2) {
                    if (parts[i] === "provider") {
                        prov = parts[i + 1] || ""
                        continue
                    }
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
                }

                if (lines.length === 0) { 
                    console.log("LYRICS DEBUG: lines length 0")
                    root.status = "not_found"
                    root.providerName = ""
                    return 
                }

                root.providerName = prov || (root.preferredProvider === "auto" ? "Automatic" : root.preferredProvider)
                root.lyricsLines = lines
                root.activeIndex = -1
                console.log("LYRICS DEBUG: ALL GOOD, status = ok, provider =", root.providerName)
                root.status = "ok"
                root.resync()
            }
        }
    }

    Timer {
        id: procRestartTimer
        interval: 100
        onTriggered: lyricsProc.running = true
    }

    function restartLyrics(prov) {
        if (prov !== undefined && prov !== "") {
            root.preferredProvider = prov
        }
        lyricsProc.running = false
        boundaryTimer.stop()
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title) { root.status = "no_info"; return }

        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration)),
            root.preferredProvider
        ]
        procRestartTimer.restart()
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { 
            root.timingOffset = 0.0
            root.restartLyrics() 
        }
        function onPlaybackStateChanged() { root.resync() }
    }

    Component.onCompleted: root.restartLyrics()
}