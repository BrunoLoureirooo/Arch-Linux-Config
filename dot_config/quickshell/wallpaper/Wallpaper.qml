// Wallpaper layer, one per screen (spec 5.3): a background-layer PanelWindow over
// the whole screen, Theme.bg with the image on top. The image is decoded at most at
// the screen's pixel size (sourceSize; with PreserveAspectCrop Qt scales it to fill
// that box), uncached, off the GUI thread.
// The main screen's instance (the leader) loads a new path first and reports the
// result to WallpaperState; the others keep showing their current image until it
// decoded, then switch (or go to Theme.bg if it failed). An image that cannot be shown
// (missing, not an image, a directory, unreadable) therefore leaves Theme.bg on every
// screen with one warning in the log, and nothing retries until `path` changes.
// Nothing loads before WallpaperState.ready (the state file has been read).
// retainWhileLoading keeps the previous image up while the next decodes (carousel
// scrolling does not flash Theme.bg). Category rice.wallpaper logs each load at info
// level, off by default (QT_LOGGING_RULES="rice.wallpaper.info=true" to see it).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

PanelWindow {
    id: root

    property string path

    readonly property bool leader: Screens.isMain(screen)
    // What this screen loads. Not a binding: a follower keeps its current image while
    // the leader is still decoding a new path.
    property string shownPath: ""

    function sync() {
        if (!WallpaperState.ready || path === "")
            return;
        const r = WallpaperState.result;
        if (leader)
            shownPath = path;
        else if (r.path === path)
            shownPath = r.state === 1 ? path : "";
        // else: the leader has no verdict for `path` yet; keep the current image.
    }

    onPathChanged: sync()
    onLeaderChanged: sync()
    Component.onCompleted: sync()

    Connections {
        target: WallpaperState
        function onReadyChanged() { root.sync(); }
        function onResultChanged() { root.sync(); }
    }

    LoggingCategory {
        id: log
        name: "rice.wallpaper"
        defaultLogLevel: LoggingCategory.Warning
    }

    // file:// URL with each path segment percent-encoded (#, ?, spaces, ...).
    function toUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/");
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "rice-wallpaper"
    color: Theme.bg

    Image {
        id: image
        anchors.fill: parent
        readonly property real dpr: root.screen ? root.screen.devicePixelRatio : 1
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        retainWhileLoading: true
        // Only once the window has its size: a 0x0 sourceSize would decode the image
        // at its full natural size.
        sourceSize: Qt.size(Math.ceil(width * dpr), Math.ceil(height * dpr))
        source: root.shownPath !== "" && width > 0 && height > 0 ? root.toUrl(root.shownPath) : ""
        onSourceChanged: {
            if (source != "")
                console.info(log, "loading", source, "on", root.screen ? root.screen.name : "?");
        }
        onStatusChanged: {
            if (root.leader && (status === Image.Ready || status === Image.Error))
                WallpaperState.report(root.shownPath, status === Image.Ready);
        }
    }
}
