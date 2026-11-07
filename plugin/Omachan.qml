import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui

Panel {
    id: root
    moduleName: "urbit.omachan"
    ipcTarget: "omachan" + moduleName.slice("urbit.omachan".length)
    implicitWidth: widget.implicitWidth
    implicitHeight: widget.implicitHeight

    readonly property string displayName: moduleName === "urbit.omachan" ? "Omachan" : "Omachan · " + moduleName.slice("urbit.omachan.".length)
    property var snapshot: null
    property string accountBinding: ""
    property bool directCredentials: false
    property int pollFailures: 0
    property bool restoreFailed: false
    property var queuedCommand: null
    property string status: ""
    property bool failed: false
    property bool busy: false
    property bool settingsOpen: false
    property bool reviewPeers: false
    property bool firstRumor: false
    property bool choosingPreferences: false
    readonly property bool available: !!snapshot && snapshot.available !== false
    readonly property string stage: !snapshot ? "login" : !available || !snapshot.palsRunning ? "install" : !snapshot.joined ? "bootstrap" : !snapshot.preferencesSet ? "preferences" : reviewPeers ? "review" : "feed"
    property int serial: 0
    property int pendingRequest: -1
    property int postRequest: -1
    property string pendingAction: ""
    readonly property color ink: Commons.Color.popups.text
    readonly property color dim: Qt.rgba(ink.r, ink.g, ink.b, 0.6)
    readonly property string bridgePath: decodeURIComponent(Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, ""))
    readonly property string hub: snapshot ? snapshot.hub || snapshot.seed || "" : ""
    readonly property bool refreshing: pendingRequest >= 0 && pendingAction === "refresh"

    ListModel { id: messageRows }
    ListModel { id: inboundRows }
    ListModel { id: suggestionRows }
    ListModel { id: peerRows }
    ListModel { id: omarchyRows }
    ListModel { id: pendingRows }
    ListModel { id: hiddenRows }

    // Preserve delegates, focus and scroll position across poll responses.
    function syncRows(model, rows, key) {
        for (let i = 0; i < rows.length; i++) {
            const ident = rows[i][key], encoded = JSON.stringify(rows[i]);
            let found = -1;
            for (let j = i; j < model.count; j++) {
                if (model.get(j).entryKey === ident) { found = j; break; }
            }
            if (found < 0) model.insert(i, {entryKey: ident, dataJson: encoded});
            else {
                if (found !== i) model.move(found, i, 1);
                if (model.get(i).dataJson !== encoded) model.setProperty(i, "dataJson", encoded);
            }
        }
        if (model.count > rows.length) model.remove(rows.length, model.count - rows.length);
    }
    function applyState(next) {
        const people = next ? next.peers.slice().sort((a,b) => a.ship.localeCompare(b.ship)) : [];
        syncRows(messageRows, next ? next.posts : [], "id");
        // An incoming follow can already be mutual. Tags do not determine friendship.
        syncRows(inboundRows, people.filter(p => p.incoming && !p.target && !p.ignored), "ship");
        syncRows(suggestionRows, people.filter(p => p.active && !p.incoming && !p.target && !p.ignored), "ship");
        syncRows(peerRows, people.filter(p => p.mutual && (!p.tagged || p.ignored)), "ship");
        syncRows(omarchyRows, people.filter(p => p.mutual && p.tagged && !p.ignored), "ship");
        syncRows(pendingRows, people.filter(p => p.target && !p.incoming && !p.ignored), "ship");
        syncRows(hiddenRows, people.filter(p => p.ignored && !p.mutual), "ship");
        if (JSON.stringify(next) !== JSON.stringify(snapshot)) snapshot = next;
    }
    function clearAccount() {
        applyState(null);
        accountBinding = ""; composer.clear(); loginCode.clear();
        distributor.clear(); queuedCommand = null;
        settingsOpen = false; reviewPeers = false; firstRumor = false; choosingPreferences = false;
        directCredentials = false;
    }
    function dispatch(value) {
        pendingRequest = value.request;
        pendingAction = value.action;
        busy = value.action !== "refresh" && value.action !== "restore";
        bridge.write(JSON.stringify(value) + "\n");
    }
    function command(action, fields) {
        if (busy || !bridge.running || (pendingRequest >= 0 && (action === "refresh" || action === "restore"))) return -1;
        const value = Object.assign({}, fields || {}, {action: action, request: ++serial, binding: accountBinding});
        if (pendingRequest >= 0) {
            // A click during a background poll runs immediately after that poll.
            queuedCommand = value;
            busy = true;
        } else dispatch(value);
        return serial;
    }
    function login(url, code) { return command("login", {url: url.trim(), code: code}); }
    function signIn() {
        if (login(loginUrl.text, loginCode.text) >= 0) loginCode.clear();
    }
    function textBytes(text) { return encodeURIComponent(text.trim()).replace(/%[A-F\d]{2}/g, "x").length; }
    function post() {
        if (!composer.text.trim() || textBytes(composer.text) > 1024) return;
        postRequest = command("post", {text: composer.text.trim()});
    }
    function peerStatus(p) {
        if (p.ignored) return p.mutual ? "Still mutual pals · excluded from Omarchy auto-accept" : p.incoming ? "They still follow you · excluded from auto-accept" : "Excluded from auto-accept";
        if (p.connected) return "Mutual · gossip connected";
        if (p.tagged) return p.mutual ? "Mutual pals · awaiting gossip connection" : "You added them · waiting for add-back";
        if (p.mutual) return "Mutual pals · no omarchy tag on your side";
        if (p.incoming) return p.active ? "They added you · accept to connect" : "They added you · awaiting a verified Omarchy claim";
        if (p.target) return "You added them · waiting for add-back";
        return "Heard through discovery";
    }
    function showSettings() {
        settingsOpen = true;
        status = "";
    }
    function choosePeers(automatic) {
        choosingPreferences = true;
        if (command("preferences", {autoAccept: automatic}) < 0) choosingPreferences = false;
    }
    function finishSetup() {
        reviewPeers = false;
        firstRumor = true;
        Qt.callLater(function() { composer.forceActiveFocus(); });
    }
    onOpenedChanged: {
        if (opened && !bridge.running) bridge.running = true;
        if (opened) {
            restoreFailed = false; pollFailures = 0;
            command(snapshot ? "refresh" : "restore");
        } else { loginCode.clear(); directCredentials = false; }
    }

    Process {
        id: bridge
        command: ["python3", "-u", "-B", root.bridgePath]
        running: true
        stdinEnabled: true
        onStarted: if (root.opened) root.command("restore")
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    const reply = JSON.parse(line);
                    if (reply.request !== root.pendingRequest) return;
                    const finished = root.pendingAction;
                    root.pendingRequest = -1;
                    root.pendingAction = "";
                    root.busy = false;
                    const wasFailed = root.failed;
                    const idleRestore = finished === "restore" && reply.ok && !reply.state;
                    if (!idleRestore) root.failed = !reply.ok;
                    if (reply.ok) {
                        root.pollFailures = 0;
                        root.restoreFailed = false;
                        root.accountBinding = reply.binding || "";
                        root.applyState(reply.state);
                        if (reply.state && !distributor.activeFocus && !distributor.text)
                            distributor.text = reply.state.distributor || "";
                        if (finished === "preferences" && root.choosingPreferences) {
                            root.reviewPeers = true; root.choosingPreferences = false;
                        }
                        if (finished === "login") root.settingsOpen = false;
                        if (finished === "post") root.status = "Posted.";
                        else if (finished === "login" || (finished === "restore" && reply.state)) root.status = "";
                        else if (finished !== "restore" && finished !== "refresh") root.status = reply.state ? reply.state.note || "" : "";
                        else if (finished === "refresh" && wasFailed) root.status = "";
                        if (reply.request === root.postRequest) { composer.text = ""; root.firstRumor = false; }
                        if (!reply.state && finished === "logout") root.clearAccount();
                        if (reply.state && (finished === "restore" || finished === "login")) { root.directCredentials = false; loginCode.clear(); }
                    } else {
                        root.status = reply.error; root.choosingPreferences = false;
                        if (reply.signedOut && root.accountBinding) root.clearAccount();
                        if (finished === "restore") root.restoreFailed = true;
                        if (finished === "refresh") root.pollFailures = Math.min(root.pollFailures + 1, 5);
                    }
                    const queued = root.queuedCommand;
                    root.queuedCommand = null;
                    if (queued && reply.ok && (queued.binding === root.accountBinding || queued.action === "login" && !root.accountBinding))
                        root.dispatch(queued);
                } catch (e) {
                    root.busy = false; root.pendingRequest = -1; root.queuedCommand = null; root.failed = true; root.status = "Connection helper returned an invalid response.";
                }
            }
        }
        onExited: {
            root.busy = false; root.pendingRequest = -1; root.queuedCommand = null; root.clearAccount(); root.failed = true;
            root.status = "Connection helper stopped. Reopen Omachan to sign in again.";
        }
    }
    Timer {
        interval: 5000 * Math.pow(2, root.pollFailures)
        running: root.opened && !root.restoreFailed
        repeat: true
        onTriggered: root.command(root.snapshot ? "refresh" : "restore")
    }
    Process {
        id: openOmabit
        command: ["timeout", "--kill-after=1", "5", "omarchy-shell", "thelifeandtimes.omabit" + root.moduleName.slice("urbit.omachan".length) + ".monitor", "applications", root.moduleName]
        onExited: function(code, status) {
            root.failed = !!(code || status);
            root.status = root.failed ? "Omabit is unavailable. Choose Enter direct credentials to sign in." : "Approve Omachan in Application Connections.";
            root.restoreFailed = false;
            if (!root.failed) root.close();
        }
    }
    Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: root.close() }

    component Body: Controls.Label {
        color: root.ink
        textFormat: Text.PlainText
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
    }
    component Action: Ui.Button {
        foreground: root.ink
        fontFamily: Style.font.family
        fontSize: Style.font.bodySmall
        focusable: true
        bordered: true
    }
    component Section: Ui.PanelSectionHeader {
        foreground: root.ink
        Layout.fillWidth: true
    }
    component PeerRow: RowLayout {
        required property string dataJson
        readonly property var peer: JSON.parse(dataJson)
        readonly property bool disconnected: peer.ignored
        readonly property bool added: peer.tagged && !peer.ignored
        objectName: "peer-" + peer.ship
        Layout.fillWidth: true
        spacing: Style.space(8)
        ColumnLayout {
            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: Style.space(3)
            Body { text: peer.ship; Layout.fillWidth: true; font.pixelSize: Style.font.body; wrapMode: Text.WrapAnywhere }
            Body { text: root.peerStatus(peer); color: root.dim; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
        }
        Action {
            objectName: "peer-action-" + peer.ship
            text: disconnected ? "Restore" : added ? "Disconnect" : peer.mutual || peer.target ? "Tag omarchy" : peer.incoming ? "Accept" : "Add"
            enabled: !root.busy && (disconnected || added || (!!root.snapshot && root.snapshot.joined && root.snapshot.palsRunning && peer.active))
            tooltipText: added ? "Remove your omarchy tag only. Their friendship and tags of you are unchanged." : disconnected ? "Allow this peer again; auto-accept may reconnect you." : "Add this pal with your omarchy tag"
            onClicked: root.command(disconnected ? "restore" : added ? "remove" : "add", {ship: peer.ship})
        }
        Ui.PanelActionButton {
            visible: !added && !disconnected
            iconText: "×"; foreground: root.ink; focusable: true
            tooltipText: "Hide suggestion and exclude it from auto-accept"
            enabled: !root.busy
            onClicked: root.command("dismiss", {ship: peer.ship})
        }
    }
    component Field: Controls.TextField {
        color: root.ink
        placeholderTextColor: root.dim
        selectionColor: Commons.Color.accent
        selectedTextColor: Commons.Color.background
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        padding: Style.space(9)
        background: Rectangle {
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
            radius: Style.cornerRadius
            border.width: 1
            border.color: parent.activeFocus ? Commons.Color.accent : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)
        }
    }

    WidgetButton {
        id: widget
        anchors.fill: parent
        bar: root.bar
        text: "※"
        fontSize: Style.space(20)
        tooltipText: root.snapshot ? "Omachan · " + root.snapshot.our : "Omachan · Sign in"
        Accessible.name: "Omachan gossip"
        onPressed: function(button) {
            if (!bridge.running) { bridge.running = true; root.status = ""; }
            if (button === Qt.RightButton && root.snapshot) { root.showSettings(); root.open(); }
            else if (button === Qt.LeftButton) { root.settingsOpen = false; root.toggle(); }
        }
    }
    KeyboardPanel {
        id: popup
        anchorItem: widget
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: content
        contentWidth: popup.fittedContentWidth(Style.space(430))
        contentHeight: popup.cappedContentHeight(Style.space(root.snapshot ? 530 : 370))

        ColumnLayout {
            id: content
            objectName: "omachan-content"
            anchors.fill: parent
            spacing: Style.space(10)
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                RowLayout {
                    id: hero
                    objectName: "omachan-hero"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Style.space(14)
                    readonly property string title: root.settingsOpen ? "Peers & settings" : root.displayName
                    readonly property string meta: root.settingsOpen ? "Your side of the connection" : "Anonymous neighborhood gossip"
                    Text { text: "※"; color: root.ink; font.family: Style.font.family; font.pixelSize: Style.font.display; textFormat: Text.PlainText }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Style.space(2)
                        Body { text: hero.title; font.pixelSize: Style.font.title; font.bold: true; Layout.fillWidth: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                        RowLayout {
                            id: metadata
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Body {
                                objectName: "header-subtitle"
                                text: hero.meta.toUpperCase()
                                color: root.dim; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                wrapMode: Text.NoWrap; elide: Text.ElideRight
                            }
                            Body {
                                objectName: "account-label"
                                visible: !!root.snapshot
                                text: root.snapshot ? root.snapshot.our : ""
                                color: root.dim; font.pixelSize: Style.font.caption
                                Layout.maximumWidth: metadata.width * 0.65
                                wrapMode: Text.NoWrap; elide: Text.ElideRight
                                Controls.ToolTip.visible: accountHover.hovered && truncated
                                Controls.ToolTip.text: text
                                HoverHandler { id: accountHover }
                            }
                        }
                    }
                }
                Ui.PanelActionButton {
                    objectName: "refresh-button"
                    visible: !!root.snapshot
                    iconText: "↻"; foreground: root.ink; bordered: true; focusable: true
                    size: Style.spacing.controlHeight
                    tooltipText: "Refresh"
                    onClicked: root.command("refresh")
                }
                Ui.PanelActionButton {
                    objectName: "back-button"
                    visible: root.settingsOpen
                    iconText: "←"; foreground: root.ink; bordered: true; focusable: true
                    size: Style.spacing.controlHeight
                    tooltipText: "Back to the feed"
                    onClicked: { root.settingsOpen = false; root.status = ""; }
                }
                Ui.PanelActionButton {
                    objectName: "settings-button"
                    visible: root.available && root.stage === "feed" && !root.settingsOpen
                    iconText: ""; foreground: root.ink; bordered: true; focusable: true
                    size: Style.spacing.controlHeight
                    tooltipText: "Peers and settings"
                    onClicked: root.showSettings()
                }
            }
            Ui.PanelSeparator { Layout.fillWidth: true; foreground: root.ink }
            ColumnLayout {
                visible: root.snapshot === null
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Style.space(10)
                Action {
                    objectName: "connect-via-omabit"
                    text: openOmabit.running ? "Opening Omabit…" : "Connect with Omabit"
                    enabled: !root.busy && !openOmabit.running && /^urbit\.omachan(?:\.[a-z][a-z0-9-]{0,31})?$/.test(root.moduleName)
                    onClicked: { loginCode.clear(); root.directCredentials = false; openOmabit.running = true; }
                }
                Action {
                    objectName: "direct-credentials"
                    text: "Enter direct credentials"; bordered: false; visible: !root.directCredentials
                    enabled: !root.busy
                    onClicked: { root.directCredentials = true; loginUrl.forceActiveFocus(); }
                }
                Action {
                    text: "Check connection"; visible: root.restoreFailed; enabled: !root.busy
                    onClicked: { root.restoreFailed = false; root.command("restore"); }
                }
                Field { id: loginUrl; visible: root.directCredentials; objectName: "login-url"; placeholderText: "https://your-ship.example"; Layout.fillWidth: true; Accessible.name: "Ship URL"; enabled: !root.busy; onAccepted: loginCode.forceActiveFocus() }
                Field { id: loginCode; visible: root.directCredentials; objectName: "login-code"; placeholderText: "+code (luscode)"; echoMode: TextInput.Password; passwordMaskDelay: 0; maximumLength: 512; enabled: !root.busy; Layout.fillWidth: true; Accessible.name: "Ship +code"; onAccepted: if (text && loginUrl.text) root.signIn() }
                Action { visible: root.directCredentials; text: root.busy ? "Signing in…" : "Sign in"; enabled: !root.busy && loginUrl.text.trim().length > 0 && loginCode.text.length > 0; onClicked: root.signIn() }
                Body { visible: root.directCredentials; text: "Your +code is never saved. This session lasts until you sign out or restart the shell."; color: root.dim; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
            }
            ColumnLayout {
                visible: !!root.snapshot && (root.stage === "install" || root.stage === "bootstrap") && !root.settingsOpen
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Style.space(12)
                Body { text: root.stage === "install" ? "Install on your ship" : "Meet the neighborhood"; font.bold: true; Layout.fillWidth: true }
                Body { text: root.stage === "install" ? "Install %omachan and, if needed, %pals from your distributor." : "The desk recommends " + root.hub + " as your first pal. Add the hub with the omarchy tag, then announce that you want to meet other Omarchy users."; Layout.fillWidth: true }
                Field { id: distributor; objectName: "distributor"; visible: root.stage === "install"; placeholderText: "~distributor-ship"; Layout.fillWidth: true; enabled: !root.busy; Accessible.name: "Distributor ship" }
                Action {
                    objectName: "bootstrap-action"
                    text: root.stage === "install" ? "Install" : root.snapshot && root.snapshot.bootstrapping ? "Adding pal…" : "Add pal & announce"
                    visible: root.stage === "install" || root.hub !== (root.snapshot ? root.snapshot.our : "")
                    enabled: !root.busy && (root.stage === "install" ? distributor.text.trim().length > 1 : root.hub.length > 1) && !(root.snapshot && root.snapshot.bootstrapping)
                    onClicked: root.stage === "install" ? root.command("install", {ship: distributor.text.trim()}) : root.command("bootstrap")
                }
                Body { visible: !!root.snapshot && root.snapshot.installing === true; text: "Installation requested. Your ship may need a minute to fetch the desks."; color: root.dim; Layout.fillWidth: true }
                Action { visible: root.stage === "install"; text: "Check again"; enabled: !root.busy; onClicked: root.command("refresh") }
                Action { visible: root.stage === "bootstrap"; text: "I'm starting a network"; enabled: !root.busy; onClicked: root.command("join") }
                Item { Layout.fillHeight: true }
                Action { text: "Sign out"; enabled: !root.busy; onClicked: root.command("logout") }
            }
            ColumnLayout {
                visible: root.stage === "preferences" && !root.settingsOpen
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Style.space(12)
                Body { text: "Let new pals in?"; font.bold: true; Layout.fillWidth: true }
                Body { text: "Auto-accept adds and tags Omarchy users whose verified discovery claims your ship hears. You can also accept each one yourself."; Layout.fillWidth: true }
                Action { objectName: "choose-manual"; text: "I'll accept pals myself"; enabled: !root.busy; onClicked: root.choosePeers(false) }
                Action { objectName: "choose-auto"; text: "Auto-accept omarchy pals"; enabled: !root.busy; onClicked: root.choosePeers(true) }
                Body { text: "You can change this in settings anytime."; color: root.dim; Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
            }
            ColumnLayout {
                visible: root.stage === "feed" && !root.settingsOpen
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Style.space(8)
                RowLayout {
                    Layout.fillWidth: true
                    Controls.TextArea {
                        id: composer
                        objectName: "composer"
                        Layout.fillWidth: true; Layout.preferredHeight: Style.space(62)
                        placeholderText: root.firstRumor ? "Send your first rumor into the void…" : "Rumor has it…"
                        placeholderTextColor: root.dim
                        color: root.ink; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap
                        font.family: Style.font.family; font.pixelSize: Style.font.body
                        padding: Style.space(8)
                        Accessible.name: "New rumor"
                        enabled: !!root.snapshot && root.snapshot.palsRunning
                        background: Rectangle { color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05); radius: Style.cornerRadius; border.width: composer.activeFocus ? 1 : 0; border.color: Commons.Color.accent }
                        Keys.onPressed: function(event) { if (event.key === Qt.Key_Return && event.modifiers & Qt.ControlModifier) { root.post(); event.accepted = true; } }
                    }
                    Action { objectName: "post-button"; text: "Post"; enabled: !root.busy && !!root.snapshot && root.snapshot.palsRunning && root.textBytes(composer.text) > 0 && root.textBytes(composer.text) <= 1024; onClicked: root.post() }
                }
                Body { visible: root.textBytes(composer.text) > 900; text: root.textBytes(composer.text) + " / 1024 bytes"; color: root.textBytes(composer.text) > 1024 ? Commons.Color.urgent : root.dim; font.pixelSize: Style.font.caption }
                Ui.PanelSeparator { Layout.fillWidth: true; foreground: root.ink }
                ListView {
                    id: rumors
                    objectName: "rumors-list"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: messageRows
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    Body { anchors.centerIn: parent; width: parent.width - 30; horizontalAlignment: Text.AlignHCenter; visible: rumors.count === 0; text: "Nothing heard yet."; color: root.dim }
                    delegate: Item {
                        required property string dataJson
                        readonly property var modelData: JSON.parse(dataJson)
                        objectName: "rumor-" + modelData.id
                        width: ListView.view.width
                        height: rumorColumn.implicitHeight + Style.space(24)
                        Column {
                            id: rumorColumn
                            width: parent.width - Style.space(10)
                            y: Style.space(8)
                            spacing: Style.space(5)
                            Body { width: parent.width; text: modelData.text }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12) }
                    }
                }
            }
            ColumnLayout {
                visible: root.available && (root.settingsOpen || root.stage === "review")
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Style.space(10)
                RowLayout {
                    Layout.fillWidth: true
                    Body { text: "Auto-accept omarchy pals"; Layout.fillWidth: true; font.pixelSize: Style.font.bodySmall }
                    Ui.ToggleSwitch {
                        objectName: "auto-accept"
                        foreground: root.ink
                        checked: !!root.snapshot && root.snapshot.autoAccept
                        busy: root.busy
                        activeFocusOnTab: true
                        onToggled: root.command("preferences", {autoAccept: !root.snapshot.autoAccept})
                        Keys.onSpacePressed: if (!root.busy) toggled()
                        Keys.onReturnPressed: if (!root.busy) toggled()
                    }
                }
                Body { text: "Disconnect removes only your omarchy tag and stops gossip. Your Pals friendship and their tags of you stay unchanged."; Layout.fillWidth: true; color: root.dim; font.pixelSize: Style.font.caption }
                Ui.PanelSeparator { Layout.fillWidth: true; foreground: root.ink }
                Flickable {
                    id: settingsScroll
                    objectName: "peers-scroll"
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight
                    ColumnLayout {
                        id: settingsColumn
                        width: settingsScroll.width
                        spacing: Style.space(12)
                        Section { text: "PEER CONNECTIONS" }
                        Body { text: "Mutual pals outside your Omarchy network."; color: root.dim; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                        Body { visible: peerRows.count === 0; text: "No other mutual pals."; color: root.dim; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                        Repeater { objectName: "mutual-peers"; model: peerRows; delegate: PeerRow {} }
                        Section { text: "OMARCHY MUTUALS" }
                        Body { text: "Mutual pals with your omarchy tag."; color: root.dim; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                        Body { visible: omarchyRows.count === 0; text: "No Omarchy mutuals yet."; color: root.dim; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true }
                        Repeater { objectName: "omarchy-peers"; model: omarchyRows; delegate: PeerRow {} }
                        Section { visible: inboundRows.count > 0; text: "INBOUND REQUESTS" }
                        Repeater { objectName: "inbound-peers"; model: inboundRows; delegate: PeerRow {} }
                        Section { visible: pendingRows.count > 0; text: "WAITING FOR ADD-BACK" }
                        Repeater { objectName: "pending-peers"; model: pendingRows; delegate: PeerRow {} }
                        Section { visible: suggestionRows.count > 0; text: "DISCOVERED PEERS" }
                        Repeater { objectName: "discovered-peers"; model: suggestionRows; delegate: PeerRow {} }
                        Section { visible: hiddenRows.count > 0; text: "DISCONNECTED / HIDDEN" }
                        Repeater { objectName: "hidden-peers"; model: hiddenRows; delegate: PeerRow {} }
                    }
                }
                Action { objectName: "finish-setup"; visible: root.stage === "review" && !root.settingsOpen; text: "Into the gossip →"; onClicked: root.finishSetup() }
                RowLayout {
                    visible: root.settingsOpen
                    Layout.fillWidth: true
                    Action { text: root.snapshot && root.snapshot.joined ? "Leave discovery" : "Join discovery"; enabled: !root.busy; onClicked: root.command(root.snapshot.joined ? "leave" : "join") }
                    Item { Layout.fillWidth: true }
                    Action { text: "Sign out"; enabled: !root.busy; onClicked: root.command("logout") }
                }
            }
            Body { visible: root.status.length > 0 && (root.failed || root.stage !== "feed" || root.settingsOpen); text: root.status; color: root.failed ? Commons.Color.urgent : root.dim; Layout.fillWidth: true; font.pixelSize: Style.font.caption; maximumLineCount: 3; elide: Text.ElideRight }
        }
    }
}
