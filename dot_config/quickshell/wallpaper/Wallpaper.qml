// Wallpaper layer, one per screen (spec 5.3): a background-layer PanelWindow over
// the whole screen, Theme.bg with the image on top. The image is decoded at most at
// the screen's pixel size (sourceSize; with PreserveAspectCrop Qt scales it to fill
// that box), uncached, off the GUI thread.
// The main screen's instance (the leader) loads a new path first and reports the
// result to WallpaperState; the others load it only once it decoded. An image that
// cannot be shown (missing, not an image, a directory, unreadable) therefore leaves
// Theme.bg on every screen with one warning in the log, and nothing retries until
// `path` changes.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

PanelWindow {
    id: root

    property string path

    readonly property bool leader: Screens.isMain(screen)
    readonly property bool mayLoad: path !== "" && (leader
        || (WallpaperState.verdictPath === path && WallpaperState.verdict === 1))

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
        // Only once the window has its size: a 0x0 sourceSize would decode the image
        // at its full natural size.
        sourceSize: Qt.size(Math.ceil(width * dpr), Math.ceil(height * dpr))
        source: root.mayLoad && width > 0 && height > 0 ? root.toUrl(root.path) : ""
        onStatusChanged: {
            if (root.leader && (status === Image.Ready || status === Image.Error))
                WallpaperState.report(root.path, status === Image.Ready);
        }
    }
}
