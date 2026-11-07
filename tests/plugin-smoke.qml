import QtQuick
import Quickshell
import Quickshell.Io
import "Omachan" as Plugin
import qs.Commons
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property var stablePeer: null
    property real peerScroll: 0
    property string rumor: "A little bird says the menu bar is open. " + Date.now()
    readonly property string ship: Quickshell.env("OMACHAN_TEST_SHIP") || "wes"
    readonly property string knownPeer: ship === "fex" ? "~wes" : "~fex"
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
    function sameRow(left, right) {
        const content = item("omachan-content");
        return Math.abs(left.mapToItem(content, 0, left.height / 2).y - right.mapToItem(content, 0, right.height / 2).y) < 1;
    }
    function peersIn(name) {
        const rows = item(name), ships = [];
        for (let i = 0; i < rows.count; i++) ships.push(rows.itemAt(i).peer.ship);
        return ships;
    }
    property var pendingCapture: null
    function capture(name, after) {
        pendingCapture = {name: name, after: after};
        captureFrame.restart();
    }
    Timer {
        id: captureFrame
        interval: 250
        onTriggered: {
            if (!app.opened) { app.open(); restart(); return; }
            const job = test.pendingCapture, target = test.item("omachan-content");
            if (!target) { console.error("Missing popup content"); Qt.exit(1); return; }
            const started = target.parent.parent.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("OMACHAN_SOURCE") + "/.dev/plugin-check/" + job.name + ".png");
                test.pendingCapture = null;
                if (job.after) job.after();
            });
            if (!started) restart();
        }
    }
    Process {
        id: fakeCode
        command: ["python3", Quickshell.env("OMACHAN_SOURCE") + "/scripts/fake-code.py", test.ship]
        stdout: SplitParser { onRead: function(code) {
            test.item("direct-credentials").clicked();
            const url = test.item("login-url"), field = test.item("login-code");
            if (!url || !field) { console.error("Login fields not found"); Qt.exit(1); return; }
            url.text = "http://127.0.0.1:" + (test.ship === "fex" ? "8101" : "8102");
            field.text = code.trim();
            app.signIn();
            if (field.text !== "") { console.error("Login field retained code"); Qt.exit(1); }
        } }
    }
    Timer {
        interval: 700; repeat: true; running: true
        onTriggered: {
            if (++test.ticks > 70 || app.failed) { console.error("UI check failed", app.status); Qt.exit(1); return; }
            if (test.pendingCapture || app.busy || app.pendingRequest >= 0) return;
            if (test.phase === 0) { test.capture("login", function() { fakeCode.running = true; }); test.phase++; }
            else if (test.phase === 1 && app.snapshot) {
                if (app.snapshot.our !== "~" + test.ship) { console.error("Wrong fake ship"); Qt.exit(1); return; }
                const content = test.item("omachan-content");
                if (test.item("account-label").text !== "~" + test.ship || test.item("omachan-hero").title !== "Omachan") { console.error("Missing account header"); Qt.exit(1); return; }
                if (!test.sameRow(test.item("account-label"), test.item("header-subtitle")) || !test.sameRow(test.item("refresh-button"), test.item("settings-button"))) { console.error("Header controls are not aligned"); Qt.exit(1); return; }
                if (test.item("composer").mapToItem(content,0,0).y >= test.item("rumors-list").mapToItem(content,0,0).y) { console.error("Composer is below the feed"); Qt.exit(1); return; }
                test.capture("rumors", function() { test.item("composer").text = test.rumor; app.post(); }); test.phase++;
            } else if (test.phase === 2) {
                if (test.item("composer").text !== "" || !app.snapshot.posts.some(p => p.text === test.rumor)) { console.error("Post was not accepted"); Qt.exit(1); return; }
                const rows = app.snapshot.posts;
                for (let i = 1; i < rows.length; i++) if (rows[i].order > rows[i-1].order) { console.error("Rumors out of order"); Qt.exit(1); return; }
                app.showSettings(); test.phase++;
            } else if (test.phase === 3) {
                // ~let is a mutual without an omarchy tag on ~fex, but a one-way
                // incoming follow on ~wes. Neither belongs in Omarchy Mutuals.
                const letPeer = app.snapshot.peers.find(p => p.ship === "~let");
                const group = test.ship === "fex" ? "mutual-peers" : "inbound-peers";
                if (!letPeer || letPeer.mutual !== (test.ship === "fex") || letPeer.tagged || test.peersIn(group).indexOf("~let") < 0 || test.peersIn("omarchy-peers").indexOf("~let") >= 0) { console.error("The reported ~let relationship is misclassified or its test fixture changed"); Qt.exit(1); return; }
                if (test.ship === "fex" && (test.peersIn("inbound-peers").indexOf("~let") >= 0 || test.item("peer-action-~let").text !== "Tag omarchy")) { console.error("Existing mutual offered inbound acceptance"); Qt.exit(1); return; }
                if (!test.sameRow(test.item("refresh-button"), test.item("back-button"))) { console.error("Settings refresh is not aligned"); Qt.exit(1); return; }
                test.stablePeer = test.item("peer-" + test.knownPeer);
                if (!test.stablePeer) { console.error("Missing known peer row"); Qt.exit(1); return; }
                const scroll = test.item("peers-scroll");
                scroll.contentY = Math.min(30, Math.max(0, scroll.contentHeight - scroll.height));
                test.peerScroll = scroll.contentY;
                test.item("composer").text = "Unsent draft stays here";
                app.command("refresh");
                if (app.busy || !test.item("post-button").enabled || !test.item("peer-action-" + test.knownPeer).enabled) { console.error("Background refresh disabled controls"); Qt.exit(1); return; }
                test.phase++;
            } else if (test.phase === 4) {
                if (test.stablePeer !== test.item("peer-" + test.knownPeer) || Math.abs(test.peerScroll - test.item("peers-scroll").contentY) > 1 || test.item("composer").text !== "Unsent draft stays here") { console.error("Refresh replaced rows, moved scroll, or lost draft"); Qt.exit(1); return; }
                if (test.item("distributor").visible) { console.error("Distributor editable in peer settings"); Qt.exit(1); return; }
                test.capture("settings", function() { app.close(); }); test.phase++;
            } else if (test.phase === 5) {
                if (!app.snapshot) { console.error("Closing lost session"); Qt.exit(1); return; }
                app.open(); app.settingsOpen = false; test.phase++;
            } else if (test.phase === 6) {
                app.command("refresh");
                const queued = app.command("logout");
                if (queued < 0 || !app.queuedCommand) { console.error("Click during refresh was dropped"); Qt.exit(1); return; }
                test.phase++;
            } else if (test.phase === 7) {
                if (app.snapshot !== null) { console.error("Queued sign out failed"); Qt.exit(1); return; }
                console.log("PASS: inline ship/subtitle, aligned header actions, mutual vs incoming Pals, top composer, receipt order, posting, stable peer rows/scroll/draft, active controls during refresh, queued clicks, reopen and logout");
                Qt.quit();
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
