import QtQuick
import Quickshell
import Quickshell.Io
import "Omachan" as Plugin
import qs.Commons
ShellRoot {
    PanelWindow {
        id: previewBar
        anchors { top: true; right: true }
        implicitWidth: 110
        implicitHeight: 34
        color: Color.background
        exclusionMode: ExclusionMode.Ignore
        property string position: "top"
        property bool vertical: false
        property int barSize: 34
        property color barForeground: Color.foreground
        property color urgent: Color.urgent
        property string fontFamily: Style.font.family
        property bool foregroundAnimationEnabled: false
        property var activePopout: null
        function requestPopout(owner) { activePopout = owner; }
        function releasePopout(owner) { activePopout = null; }
        function showTooltip(item, text) {}
        function hideTooltip(item) {}
        Plugin.Omachan {
            id: app
            anchors.right: parent.right
            bar: previewBar
            Component.onCompleted: Qt.callLater(function() { app.open(); })
        }
    }
}
