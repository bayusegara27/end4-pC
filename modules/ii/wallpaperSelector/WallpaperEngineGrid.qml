import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

/**
 * The Wallpaper Engine library, browsable from inside the shell.
 *
 * The listing comes from wpe-manager's own scanner (scripts/colors/wpe-library.sh)
 * so titles and previews match its GUI. Workshop previews are usually animated
 * GIFs; Image renders their first frame, so no thumbnail pipeline is involved.
 *
 * Applying is delegated to wpe-set-wallpaper.sh, which has to restart the
 * manager for the choice to stick — see the comment there.
 */
Item {
    id: root

    signal wallpaperSelected(string path)

    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property real cellWidth: grid.cellWidth
    property real cellHeight: grid.cellHeight

    property var allWallpapers: []
    property string activeId: ""

    readonly property var wallpapers: {
        const query = (Wallpapers.searchQuery ?? "").trim().toLowerCase();
        if (query.length === 0)
            return root.allWallpapers;
        return root.allWallpapers.filter(entry => (entry.title ?? "").toLowerCase().includes(query));
    }

    function moveSelection(delta) {
        grid.currentIndex = Math.max(0, Math.min(root.wallpapers.length - 1, grid.currentIndex + delta));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    function activateCurrent() {
        const entry = root.wallpapers[grid.currentIndex];
        if (entry) root.apply(entry.id);
    }

    function apply(id) {
        if (!id) return;
        root.activeId = id;
        Quickshell.execDetached(["bash", Directories.wpeSetWallpaperScriptPath, id]);
    }

    function reload() {
        libraryProc.running = false;
        libraryProc.running = true;
    }

    Process {
        id: libraryProc
        running: true
        command: ["bash", Directories.wpeLibraryScriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.allWallpapers = JSON.parse(text);
                } catch (e) {
                    root.allWallpapers = [];
                    console.warn("[WallpaperEngineGrid] could not read the library:", e);
                }
            }
        }
    }

    // Which wallpaper is actually on screen, straight from wpe-manager's
    // concrete state, so the grid stays right even when it is changed from
    // wpe-manager itself.
    FileView {
        id: engineView
        path: Directories.wpeEnginePath
        watchChanges: true
        // Explicit id: a bare reload() inside here would bind to this FileView's
        // own method, not the library reload above, which is easy to misread.
        onFileChanged: engineView.reload()
        onLoaded: {
            try {
                const running = JSON.parse(text());
                const entries = Object.keys(running).map(screen => running[screen]?.id).filter(id => !!id);
                root.activeId = entries.length > 0 ? entries[0] : "";
            } catch (e) {
                root.activeId = "";
            }
        }
        onLoadFailed: error => {}
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.wallpapers.length === 0
        color: Appearance.colors.colSubtext
        horizontalAlignment: Text.AlignHCenter
        text: root.allWallpapers.length === 0
            ? Translation.tr("No Wallpaper Engine library found.\nCheck the library folder in wpe-manager.")
            : Translation.tr("No wallpaper matches that search.")
    }

    GridView {
        id: grid
        anchors.fill: parent
        visible: root.wallpapers.length > 0

        cellWidth: width / root.columns
        cellHeight: cellWidth / root.previewCellAspectRatio
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}

        model: root.wallpapers

        delegate: MouseArea {
            id: cell
            required property var modelData
            required property int index

            width: grid.cellWidth
            height: grid.cellHeight
            hoverEnabled: true
            onEntered: grid.currentIndex = index
            onClicked: root.apply(cell.modelData.id)

            Rectangle {
                anchors.fill: parent
                anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
                radius: Appearance.rounding.normal
                color: (cell.index === grid.currentIndex || cell.containsMouse)
                    ? Appearance.colors.colPrimary
                    : (cell.modelData.id === root.activeId)
                        ? Appearance.colors.colSecondaryContainer
                        : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.wallpaperSelectorItemPadding
                    spacing: 4

                    Item {
                        width: parent.width
                        height: parent.height - label.height - parent.spacing

                        StyledImage {
                            id: preview
                            anchors.fill: parent
                            source: Qt.resolvedUrl(cell.modelData.preview)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // Decode at roughly cell size: the library is 87
                            // items and some previews are multi-megabyte.
                            sourceSize.width: Math.max(1, Math.round(grid.cellWidth))
                            clip: true
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: preview.width
                                    height: preview.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }
                    }

                    StyledText {
                        id: label
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: cell.modelData.title ?? cell.modelData.id
                        color: (cell.index === grid.currentIndex || cell.containsMouse)
                            ? Appearance.colors.colOnPrimary
                            : (cell.modelData.id === root.activeId)
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer0
                    }
                }
            }
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: grid.width
                height: grid.height
                radius: Appearance.rounding.screenRounding + 5
            }
        }
    }
}
