# Omachan

An experimental `%rumors` derivative for Omarchy users, with `%pals` as its only additional Urbit app dependency. The Urbit agent, ship-hosted web app, and native Omarchy bar popup are in this repository.

Discovery shares **signed membership claims**. The board shares **unattributed text**. They use separate channels: discovery needs explicit registration, while gossip requires mutual tagged Pals. The bootstrap is an ordinary participant.

## Try the running draft

Four disposable fake ships run in tmux session `omachan-dev`, with one window per ship, under `~/temp-ur/fakeships`. Each uses `--snap-time 60`, `--no-dock`, and a loopback HTTP listener.

| Ship | Web interface | Demo role |
| --- | --- | --- |
| `~fex` | <http://127.0.0.1:8101/apps/omachan/> | Participant / default first contact |
| `~wes` | <http://127.0.0.1:8102/apps/omachan/> | Board participant |
| `~sev` | <http://127.0.0.1:8103/apps/omachan/> | Board participant |
| `~let` | <http://127.0.0.1:8104/apps/omachan/> | Fresh-install/onboarding test client |

All four ships have joined discovery. `~fex` has auto-accept enabled; `~wes` and `~sev` keep manual control. The network test finishes with an all-to-all tagged friendship graph; any ship can publish or relay, including `~fex`. No ship has a special discovery-only role.

The **※** bar icon opens a plain message feed in local arrival order (newest received first) and a small composer. The header shows your signed-in ship beside the subheader, with refresh beside **⚙**. Use **⚙** (or right-click the bar icon) for peers and the auto-accept setting. **Peer Connections** lists mutual pals outside your Omarchy network; **Omarchy Mutuals** lists mutual pals with your `omarchy` tag. Incoming one-way follows and outgoing pals waiting for add-back have separate sections. Pals exposes your local tags; each ship checks its own tag before accepting a gossip connection. The composer sits above the newest-first feed. Closing the popup preserves your login. Escape dismisses it.

In the sign-in view, **Connect with Omabit** opens Application Connections in
Omabit v0.3.7. Select your ship, approve **Omachan** (`urbit.omachan`), and
choose **Connect**. Reopen Omachan to read the feed or set up its desks. The
approval gives Omachan an independent Eyre owner session with ship-wide access.
It saves the cookie in your unlocked desktop keyring and sends app requests
directly to the selected ship. To revoke that session, use **Disconnect** in
Omabit and follow any cleanup action shown there. Signing out in Omachan
removes its local copy. Sign out of a direct account before approving a new one.

For standalone sign-in, choose **Enter direct credentials**. Use a ship URL such as `http://127.0.0.1:8102` and its **+code** (luscode):

```sh
python3 scripts/fake-code.py wes   # or sev / fex; prints only that fake's +code
tmux attach -t omachan-dev
```

The +code goes to the Python helper over stdin, is cleared from the input field, and is never saved or passed in process arguments. Standalone cookies stay in the helper's memory until sign-out, plugin unload, or shell restart. Standalone sign-in uses HTTPS for remote ships and accepts loopback HTTP. Omabit also supports an explicitly approved LAN HTTP origin. One account is supported per widget instance.

To run an isolated preview without changing shell settings:

```sh
bash scripts/preview-plugin.sh
# When finished:
quickshell kill -p .dev/plugin-preview
```

To install the local build on your bar:

```sh
bash scripts/install-plugin.sh
```

Browser tabs still let you inspect each ship independently.

## How people join

1. Sign into the bar plugin with Omabit or the ship's URL and +code.
2. If `%omachan` is absent, enter a distributor and choose **Install**. The helper installs `%pals` from that source too if missing; an existing Pals source is preserved. The distributor must serve both desks. The login stays in memory during installation.
3. Choose **Add pal & announce**. The ship adds the desk-recommended hub with the `omarchy` tag, waits for Pals to acknowledge, then broadcasts its signed discovery claim. The desk supplies the recommended hub, independently of its software distribution source.
4. Choose manual acceptance or **Auto-accept omarchy pals**, then review pals and pending connections.
5. Enter the feed and send the first rumor into the void.

A distributor starting a new network can choose **I'm starting a network**, then enable auto-accept. No participant needs a special role. Auto-accept is a persistent, ship-side preference, off by default, and continues working while the plugin is closed. It adds/tags only fresh active claims verified against current ship keys. Removed or hidden peers stay excluded. Accepting a claim preserves other Pals tags. **Restore** makes a hidden peer eligible for auto-accept again.

The web app exposes the same preference under **Connection** and keeps its detailed peer views. Registration remains explicit: enabling auto-accept alone does not announce an unjoined ship.

Every board edge requires mutual Pals friendship and each side's own `omarchy` tag on the other. Pals does not expose the remote party's tag as a shared assertion; the two agents enforce their own tags when sending, receiving, and accepting subscriptions. Removing a tag blocks traffic immediately, even before the subscription cleanup timer runs.

Any joined participant can exchange discovery claims. The distributor is an ordinary starting point, with no registration database, approval authority, or special signing key. The recommended hub only helps discovery start. It does not add a friendship, and it does not exclude that ship from gossip. Once both sides add/tag each other, the distributor receives, proxies, and publishes like every other participant. With a small graph, participants should assume their posts may be attributable.

**Withdraw claim** stops introducing you and gossips a signed withdrawal. It preserves friendships and existing board participation. **Remove omarchy tag** closes your board relationship while preserving the pal and other tags. **Hide** dismisses a suggestion locally; **Restore suggestion** clears that exclusion, so auto-accept may add the peer.

## Distribution and hub defaults

The release desk's `lib/omachan-config.hoon` separates two identities:

- Software distributor: `~dister-dozzod-sarlev`.
- Recommended discovery hub: `~sogryp-hoster-dozzod-sarlev`.

The hub is an ordinary participant that can run `%pals`, opt into discovery, and enable auto-accept. It can also host the planned Tlon community independently; Omachan does not require Tlon and no group link has been configured yet. Peer settings display no editable distributor/hub field. The first-install screen still accepts an installation source, defaulting to the release distributor; after installation, onboarding reads the hub from the desk.

`scripts/install-desk.sh` applies a fake-only configuration using `~fex` for both roles. It does not deploy to either live ship. Existing local seed choices are preserved on upgrades; the `config` action remains available for local development/admin use.

**Disconnect** removes only your `omarchy` tag and excludes that peer from auto-accept. It preserves their friendship and tags of you, as well as your other Pals tags. Mutual pals remain visible under **Peer Connections** with a **Restore** action.

## What “anonymous” means here

Posts contain no author identity or signature. Neither UI displays an author. Like Suite, the author flips a coin: broadcast now, or privately pass the post to a random eligible pal. Each private proxy makes the same choice, without spending the two-hop broadcast budget. There is no required first handoff; if no eligible proxy remains, the ship broadcasts.

**A direct peer sees the immediate sender, who may be the author or a proxy.** A distance-one post identifies the broadcast starting point, not necessarily the author. This is not a 50% guarantee of anonymity: timing, a small friendship graph, and cooperating peers can still expose the source. There is no mixing or cover traffic. Discovery membership is deliberately identified and signed; a signature proves control of a ship, not that it runs Omarchy.

Do not treat this draft as protection against a curious or hostile neighbor. Relays can copy posts, alter unsigned posts, or lie about hop distance. Stronger source anonymity is a separate protocol decision.

## Repository and checks

- `desk/`: Kelvin 408 Gall agent, bundled utility libraries, protocol marks, and static web UI. No `%profile`, `%face`, external web service, npm build, or extra installed Gall agent is required.
- `plugin/`: native QML bar popup and a Python standard-library HTTP helper.
- `manifest.json`: Omarchy shell plugin manifest (`urbit.omachan`).
- [DEVELOPMENT.md](DEVELOPMENT.md): installing the desks, running the fake network, packaging the plugin, and tests.
- [docs/protocol.md](docs/protocol.md): wire formats, authorization, limits, and remaining work.

```sh
python3 -m unittest discover -s tests -v
node --check desk/web/app.js
bash scripts/package-plugin.sh
bash scripts/check-plugin.sh     # native UI against the local ~wes fake
python3 scripts/check-network.py  # protocol regression on fex/wes/sev
python3 scripts/check-auto-accept.py  # also exercises let; leaves fex auto-accept on
```

This is a working local draft, not a livenet release. Live Azimuth key rotation, breach recovery, large networks, and long offline periods have not been exercised end to end.

## Attribution

Based on Fang's MIT-licensed [suite](https://github.com/fang-/suite), especially [`%rumors`](https://github.com/fang-/suite/blob/master/app/rumors.hoon), `%pals`, and the gossip protocol design. The inspected upstream snapshot was `b69ce154ae6ce906c2598cd46c806158b51b8a0f`. Discovery and the restricted board transport are a new protocol and are not wire-compatible with `%rumors`.

Signing and development-helper patterns were adapted from the local MIT-licensed Omart project; its notice is in `licenses/omart-MIT.txt`. Standard Gall, HTTP, and docket helpers are vendored with the desk. The original suite notice is retained in `LICENSE`. The docket's website currently points to upstream until an Omachan publication URL is selected.
