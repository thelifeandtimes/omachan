import QtQuick
import Quickshell
import Quickshell.Io
import "Omachan" as Plugin
import qs.Commons
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property string rumor: "A little bird says the menu bar is open. " + Date.now()
    function find(node, name, seen) {
        if (!node || seen.indexOf(node) >= 0) return null;
        seen.push(node);
        if (node.objectName === name) return node;
        const groups = [node.data, node.children, node.contentItem];
        for (const group of groups) {
            if (!group) continue;
            const items = group.length === undefined ? [group] : group;
            for (let i = 0; i < items.length; i++) {
                const result = find(items[i], name, seen);
                if (result) return result;
            }
        }
        return null;
    }
    function item(name) { return find(app, name, []); }
    function capture(name, after) {
        const target = item("omachan-content");
        if (!target) { console.error("Missing popup content"); Qt.exit(1); return; }
        target.parent.parent.grabToImage(function(result) { result.saveToFile(Quickshell.env("OMACHAN_SOURCE") + "/.dev/plugin-check/" + name + ".png"); if (after) after(); });
    }
    Process {
        id: fakeCode
        command: ["python3", Quickshell.env("OMACHAN_SOURCE") + "/scripts/fake-code.py", "let"]
        stdout: SplitParser { onRead: function(code) {
            test.item("direct-credentials").clicked();
            const url = test.item("login-url"), field = test.item("login-code");
            if (!url || !field) { console.error("Login fields not found"); Qt.exit(1); return; }
            url.text = "http://127.0.0.1:8104";
            field.text = code.trim();
            app.signIn();
            if (field.text !== "") { console.error("Login field retained code"); Qt.exit(1); }
        } }
    }
    Timer {
        interval: 700; repeat: true; running: true
        onTriggered: {
            if (++test.ticks > 160 || app.failed) { console.error("UI check failed", app.status); Qt.exit(1); return; }
            if (app.busy) return;
            if (test.phase === 0) { test.capture("onboard-login", function() { fakeCode.running = true; }); test.phase++; }
            else if (test.phase === 1 && app.snapshot) {
                if (app.snapshot.our !== "~let" || app.stage !== "bootstrap") { console.error("Expected fresh bootstrap screen", app.stage); Qt.exit(1); return; }
                test.capture("onboard-bootstrap", function() { test.item("bootstrap-action").clicked(); }); test.phase++;
            } else if (test.phase === 2 && app.stage === "preferences") {
                if (!app.snapshot.peers.some(p => p.ship === "~fex" && p.tagged)) { console.error("Announced before adding first pal"); Qt.exit(1); return; }
                test.capture("onboard-preferences", function() { test.item("choose-manual").clicked(); }); test.phase++;
            } else if (test.phase === 3 && app.stage === "review") {
                if (app.snapshot.autoAccept) { console.error("Manual preference ignored"); Qt.exit(1); return; }
                test.capture("onboard-peers", function() { test.item("finish-setup").clicked(); }); test.phase++;
            } else if (test.phase === 4 && app.stage === "feed") {
                if (!app.firstRumor) { console.error("Missing first rumor invitation"); Qt.exit(1); return; }
                test.capture("onboard-feed", function() { test.item("composer").text = test.rumor; app.post(); }); test.phase++;
            } else if (test.phase === 5) {
                if (app.firstRumor || !app.snapshot.posts.some(p => p.text === test.rumor)) { console.error("First rumor failed"); Qt.exit(1); return; }
                app.showSettings(); test.phase++;
            } else if (test.phase === 6) {
                test.item("auto-accept").toggled(); test.phase++;
            } else if (test.phase === 7) {
                if (!app.snapshot.autoAccept) { console.error("Auto-accept toggle failed"); Qt.exit(1); return; }
                app.command("logout"); test.phase++;
            } else if (test.phase === 8) {
                if (app.snapshot !== null) { console.error("Logout failed"); Qt.exit(1); return; }
                console.log("PASS: native first-pal bootstrap, announcement, manual choice, peer review, first rumor, settings auto-accept and logout"); Qt.quit();
            }
        }
    }

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
