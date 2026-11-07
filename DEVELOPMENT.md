# Development

Run commands from this repository. Requirements: Urbit/Vere with Kelvin 408 support, `tmux`, Python 3, `nc`, and a browser. Plugin checks additionally use Omarchy, Quickshell, Qt Quick Controls, and `qmllint`. There is no Python package install or web build step.

## Fake ships

The existing test piers are:

```
~/temp-ur/fakeships/fake-fex
~/temp-ur/fakeships/fake-wes
~/temp-ur/fakeships/fake-sev
```

They were new identities when created for this project. The script only targets those piers and tmux windows in `omachan-dev`. It does not touch the existing `urbit-prod` session or other piers. Verify identity/port availability before reusing the script on another machine.

```sh
bash scripts/fakenet.sh start
bash scripts/fakenet.sh status
tmux attach -t omachan-dev
```

`start` skips an existing window, resumes an existing project pier, and refuses to overwrite an unexpected non-pier directory. Vere's `--snap-time` is measured in minutes; the configured value is 60 on all three processes. Ports 8101–8103 bind to `127.0.0.1`. Fake identities must remain on the fake network.

For an individual Dojo command:

```sh
bash scripts/fakenet.sh dojo wes '+code'
```

## Install desks on a new fake

The running piers already have both desks installed. To reproduce the initial setup on a freshly booted project fake, run these Dojo commands one at a time, waiting for each to finish:

```hoon
|mount %base
|merge %pals our %base
|mount %pals
|merge %omachan our %base
|mount %omachan
```

Obtain the pinned suite sources if `.dev/suite` is absent:

```sh
mkdir -p .dev
git clone https://github.com/fang-/suite .dev/suite
git -C .dev/suite checkout b69ce154ae6ce906c2598cd46c806158b51b8a0f
```

Copy the desks, substituting only one of `fex`, `wes`, or `sev`:

```sh
bash scripts/install-pals-to-pier.sh .dev/suite "$HOME/temp-ur/fakeships/fake-wes"
bash scripts/install-desk.sh wes
```

Then, in that ship's Dojo, commit and install each desk after its preceding command completes:

```hoon
|commit %pals
|install our %pals
|commit %omachan
|install our %omachan
```

The Pals copy script dereferences upstream package symlinks and supplies the bundled/current desk helpers. `%pals` is otherwise unmodified. Upstream Pals adds `~paldev` on first boot; the regression setup removes that unrelated default from these local test ships if needed. A live user can keep their existing Pals configuration.

For code changes to an already installed desk:

```sh
bash scripts/sync.sh wes
```

This copies `desk/` into the mounted desk and sends `|commit %omachan`. Check the `wes` tmux window for compile/reload errors; a successful copy alone is not a successful compilation. Repeat for the other two ships for protocol changes. The script does not delete stale files; remove intentionally deleted desk files from the mounted copy when necessary.

## Test

```sh
python3 -m unittest discover -s tests -v
node --check desk/web/app.js
bash scripts/package-plugin.sh
python3 scripts/check-network.py
```

The integration runner has a fixed allowlist of the three project fake ships and communicates through their local `conn.sock` sockets and authenticated loopback HTTP sessions. It retrieves their login codes in memory. It intentionally changes their Pals edges, discovery membership and bootstrap settings, and publishes uniquely named test posts. Do not use these disposable ships for personal data.

The runner checks:

- Signed discovery without automatic Pals additions; explicit opt-in defaults.
- Signature verification, forged identities, expiry/future timestamps, and revision ordering.
- Withdrawal followed by replay, and corrupt signatures arriving through a valid discovery peer.
- Manual add-back, cached board catch-up, live delivery, and no gossip to an untagged bootstrap.
- Immediate blocking after a tag-only Pals edit, preserving unrelated tags.
- Discovery relayed through an ordinary participant and board delivery across a chain with deduplication.
- Suite-style randomized private passes, including live acceptance and rejection after tag removal and bootstrap participation after mutual tagging.
- Deterministic Hoon routing assertions in `tests/board.hoon`: both coin outcomes at origin/proxy, preserved two-hop public budget, no private snapshot leaks, acknowledgments, 30-second deadlines, negative-ack/timeout retries, stale events, duplicate/conflicting IDs, overdue work on reload, eligibility changes, and cache eviction. These inspect returned cards without sending them.
- Authentication, same-origin mutation checks, and post-size limits.
- Missing `%pals` closes peer eligibility and rejects publishing; resumption recovers service.

On exit all three fake ships are ordinary tagged mutuals, with `~fex` the first contact for the other two. Test post history remains until the 14-day retention window expires. The protocol has no authenticated global delete operation for unattributed posts.

Unit tests check helper URL handling, redirect rejection, credential-safe responses, and failed-login session cleanup. The native smoke test loads the real popup in a separate Quickshell instance, fills the URL/+code inputs for `~wes`, verifies clearing the secret, reads ordered rumors, posts a test rumor, opens peer settings, closes/reopens without losing the session, and signs out. Screenshots of just the popup are saved under `.dev/plugin-check/`. This does not establish compatibility with every Omarchy release or theme.

## Native plugin

```sh
bash scripts/preview-plugin.sh
```

The preview imports the installed shell's read-only `Commons` and `Ui` modules. Override `OMACHAN_SHELL_SOURCE` if it is elsewhere. It creates only project-local preview files and runs separately from the main shell. Escape closes the popup while preserving its session. Stop the isolated instance with `quickshell kill -p .dev/plugin-preview` to discard the session.

```sh
bash scripts/package-plugin.sh
```

The package is written to `.dev/plugin-package/`, containing the manifest, plugin files, and license notices, and validated with Omarchy and `qmllint`. Validate this package instead of the development repository: the ignored suite checkout contains symlinks that the Omarchy validator rejects.

```sh
bash scripts/check-plugin.sh
bash scripts/install-plugin.sh
```

The installer validates the package, backs up an existing installed Omachan copy and shell settings, copies it into `~/.config/omarchy/plugins/urbit.omachan`, and enables only this bar widget. The shell hot-reloads it; no shell restart is required. Click **※** or use `omarchy-shell omachan open`. Right-click **※** or click **⚙** to accept peers and change settings. Disable it with `omarchy plugin disable urbit.omachan`.

For a published Git repository, the root manifest supports the normal `omarchy plugin add` workflow. Publishing and assigning a keybinding have not been performed.

## Before a livenet release

Choose the real distribution ship and repository URL; test installation from that source, subscription recovery across actual disconnections, key rotations/breaches, and malformed traffic at volume. The selected anonymity model is Suite's 50/50 proxy pass, without a required initial handoff. Further anonymity claims would need a separate review. State version `%2` preserves `%0`/`%1` data and seeds local arrival order from the old timestamps. Auto-accept defaults off after migration.

## Auto-accept and onboarding checks

`bash scripts/fakenet.sh start-onboarding` creates/resumes `~let` at port 8104, also in `omachan-dev` with `--snap-time 60`. The default `start` resumes the original three ships and `~let` if its pier already exists. All four are under `~/temp-ur/fakeships`.

For first-run installation, make `%pals` and `%omachan` public on fake `~fex` (`|public %pals` and `|public %omachan`). Sign into fresh `~let` through the native helper and choose `~fex` as distributor. It installs both desks over Clay using Hood, then the QML wizard handles first-pal registration. `bash scripts/check-plugin.sh onboarding` exercises the wizard against a freshly installed, unjoined `~let`; it is intentionally not a repeatable check against an already onboarded ship. `bash scripts/check-plugin.sh` is the repeatable feed/login/settings check on `~wes`.

`python3 scripts/check-auto-accept.py` runs after installation/onboarding. It checks automatic add-back, withdrawn-claim replay, forged identity, hidden peers, preservation of other tags, and persistence across suspend/revive. It leaves `~fex` and `~let` auto-accepting; `~wes` and `~sev` stay manual so their pending-peer interface is useful to try.

The native feed is local receipt order, with no identities or timestamps. The wire format and Suite-style 50/50 forwarding choice are unchanged. Both interfaces share the ship-side `preferences {autoAccept}` setting.

## Widget styling and polling checks

The widget uses Omarchy's shared `PanelHero`, `PanelActionButton`, `Button`, `ToggleSwitch`, and section styles. `bash scripts/check-plugin.sh` also checks the signed-in ship header, composer position, stable peer-row instances and scroll position across refresh, draft preservation, enabled controls during polls, and a queued user action during a poll. Screenshots land in `.dev/plugin-check`.

The production desk defaults are in `desk/lib/omachan-config.hoon`; the pre-install bridge fallback is `DEFAULT_DISTRIBUTOR`. `scripts/install-desk.sh` overlays a fake-only config pointing both roles to `~fex`. Only fake piers are updated by these scripts. Distribution source and discovery hub are separate values; do not publish the fake overlay as a production release.
