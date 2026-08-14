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

    Timer {
        id: syncTimer
        interval: 50
        repeat: true
        running: root.status === "ok" && root.lyricsLines.length > 0
        onTriggered: {
            const pos = (root.activePlayer?.position ?? 0) + 1.5
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
        }
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                console.log("LYRICS DEBUG READ:", trimmed.substring(0, 100) + "... LENGTH:", trimmed.length)
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }

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
                for (let i = 0; i < parts.length - 1; i += 2) {
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
                }

                if (lines.length === 0) { 
                    console.log("LYRICS DEBUG: lines length 0")
                    root.status = "not_found"; 
                    return 
                }

                root.lyricsLines = lines
                root.activeIndex = -1
                console.log("LYRICS DEBUG: ALL GOOD, status = ok")
                root.status = "ok"
            }
        }
    }

    Timer {
        id: procRestartTimer
        interval: 100
        onTriggered: lyricsProc.running = true
    }

    function restartLyrics() {
        lyricsProc.running = false
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title || !artist) { root.status = "no_info"; return }

        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration))
        ]
        procRestartTimer.restart()
    }

    property string lastTitle: ""
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            let currentTitle = root.activePlayer ? root.activePlayer.trackTitle : ""
            if (currentTitle !== root.lastTitle && currentTitle !== "") {
                root.lastTitle = currentTitle
                root.restartLyrics()
            }
        }
    }

    Component.onCompleted: root.restartLyrics()
}