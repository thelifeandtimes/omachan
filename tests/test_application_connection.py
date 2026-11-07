"""Isolated receiver/recovery regressions. Only the identity probe and keyring are substitutes."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.request

SOURCE = Path(__file__).resolve().parents[1] / "plugin"
sys.path.insert(0, str(SOURCE))
import receive_connection as receiver
from app_connection import store as storage
from app_connection.instance import INSTANCE
from app_connection.offer import HandoffError


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.store = storage.Store(self.directory / "account.json")
        self.secrets = {}
        self.patch(self.store, "secret", self.secret)
        self.patch(storage, "secret_present", lambda instance, key: key in self.secrets)
        self.patch(receiver, "check_identity", lambda session: None)
        self.binding = dict(version=1, plugin_id=INSTANCE.plugin_id, profile=INSTANCE.profile,
                            request_id="a"*32, connection_id="b"*32)
        self.session = dict(origin="https://fixture.invalid", ship="~zod", cookie_name="urbauth-~zod",
                            cookie_value="private-fixture-value", expires=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat())

    def patch(self, target, name, value):
        replacement = patch.object(target, name, value)
        replacement.start()
        self.addCleanup(replacement.stop)

    def secret(self, action, key, data=b""):
        if action == "store":
            self.secrets[key] = data
        elif action == "lookup":
            return self.secrets[key]
        elif action == "clear":
            del self.secrets[key]
        return b""

    def accept(self, **changes):
        return receiver.accept(json.dumps({**self.binding, "session": self.session, **changes}), self.store)

    def reconcile(self, **changes):
        return receiver.reconcile(json.dumps({**self.binding, "action": "reconcile", "origin": self.session["origin"],
                                               "ship": self.session["ship"], **changes}), self.store)

    def test_accept_cleanup_and_permanent_replay_receipt(self):
        self.assertEqual(self.accept(), dict(self.binding, status="accepted"))
        with self.assertRaisesRegex(HandoffError, "account-exists"):
            self.accept(request_id="c"*32)
        with self.assertRaisesRegex(HandoffError, "attempt-changed"):
            self.reconcile(connection_id="c"*32)
        self.assertEqual(len(self.secrets), 1)
        self.assertEqual(self.reconcile()["outcome"], "removed")
        self.assertEqual(self.reconcile()["outcome"], "removed")
        with self.assertRaisesRegex(HandoffError, "recovery-required"):
            self.accept()
        self.assertFalse(self.secrets)
        for file in self.directory.rglob("*"):
            if file.is_file():
                self.assertNotIn(self.session["cookie_value"].encode(), file.read_bytes())
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)

    def test_lost_keyring_write_reply_recovers_only_the_recorded_request(self):
        def interrupted(action, key, data=b""):
            self.secret(action, key, data)
            raise HandoffError("keyring-unavailable")
        with patch.object(self.store, "secret", interrupted):
            with self.assertRaisesRegex(HandoffError, "keyring-unavailable"):
                self.accept()
        self.assertIsNone(self.store.account())
        self.assertEqual(len(self.secrets), 1)
        with self.assertRaisesRegex(HandoffError, "recovery-required"):
            self.accept(request_id="c"*32)
        self.assertEqual(self.reconcile()["outcome"], "absent")
        self.assertFalse(self.secrets)

    def test_locked_keyring_retains_pending_cleanup_until_explicit_reconcile(self):
        self.accept()
        with patch.object(storage, "secret_present", side_effect=HandoffError("keyring-unavailable")):
            with self.assertRaisesRegex(HandoffError, "keyring-unavailable"):
                self.reconcile()
        self.assertEqual(self.store.account()["application_request_id"], self.binding["request_id"])
        self.assertTrue(self.secrets)
        self.assertEqual(self.reconcile()["outcome"], "removed")

    def test_newer_account_survives_old_recovery(self):
        self.accept()
        replacement = {"baseUrl": self.session["origin"], "ship": "zod"}
        self.store.path.write_text(json.dumps(replacement))
        self.assertEqual(self.reconcile()["outcome"], "superseded")
        self.assertEqual(self.store.account(), replacement)
        self.assertFalse(self.secrets)

    def test_refuse_wrong_recipient_and_expired_token_before_probe(self):
        with patch.object(receiver, "check_identity") as probe:
            for override in ({"profile": "other"}, {"plugin_id": "other"},
                             {"version": True}, {"session": dict(self.session, expires="2000-01-01T00:00:00Z")}):
                with self.subTest(override=tuple(override)), self.assertRaises(HandoffError):
                    self.accept(**override)
            probe.assert_not_called()
        self.assertFalse(self.store.path.exists())

    def test_installed_helper_works_with_only_its_declared_inventory(self):
        import shutil
        plugin = SOURCE.parent
        declaration = json.loads((plugin/"application-connection.json").read_text())
        generation = self.directory/"generation"
        for name in declaration["files"]:
            target = generation/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(plugin/name, target)
        entry = generation/declaration["entry"]
        bootstrap = "import sys,runpy;sys.path.insert(0,sys.argv[1]);sys.argv=sys.argv[2:];runpy.run_path(sys.argv[0],run_name='__main__')"
        proc = subprocess.run([sys.executable, "-I", "-S", "-B", "-c", bootstrap, str(entry.parent), str(entry)],
                              input=b'{"version":1,"version":1}', capture_output=True, check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(json.loads(proc.stdout), {"version": 1, "status": "rejected", "code": "invalid"})
        self.assertEqual(proc.stderr, b"")

    def test_cookie_is_bound_to_origin_and_expiry(self):
        self.accept()
        cookie = storage.ApprovedCookie(self.store.session(self.store.account()))
        good = urllib.request.Request(self.session["origin"] + "/~/name")
        cookie.http_request(good)
        self.assertEqual(good.get_header("Cookie"), "urbauth-~zod=private-fixture-value")
        other = urllib.request.Request(self.session["origin"] + ":9999/~/name")
        with self.assertRaisesRegex(HandoffError, "wrong-origin"):
            cookie.http_request(other)
        self.assertFalse(other.has_header("Cookie"))
        cookie.expires = datetime.now(timezone.utc) - timedelta(seconds=1)
        with self.assertRaisesRegex(HandoffError, "expired"):
            cookie.http_request(good)

    def test_running_bridge_adopts_then_drops_revoked_account_before_post(self):
        import bridge
        client = bridge.Client(self.store)
        self.assertIsNone(client.restore())
        self.accept()
        with patch.object(client, "state", return_value={"our": "~zod"}):
            self.assertEqual(client.restore()["our"], "~zod")
        self.assertEqual(client.binding, self.binding["request_id"])
        self.reconcile()
        with patch.object(client.opener, "open") as send:
            with self.assertRaisesRegex(ValueError, "connection changed"):
                client.act({"action": "post", "text": "old draft"})
            send.assert_not_called()
        self.assertEqual(client.url, "")

    def test_direct_login_excludes_approval_until_bridge_signs_out(self):
        import bridge
        client = bridge.Client(self.store)
        # Acquire the same lifetime lease held by login, without contacting a ship.
        client.direct_lease.enter_context(self.store.locked("direct"))
        with self.assertRaisesRegex(HandoffError, "account-busy"):
            self.accept()
        client.logout()
        self.assertEqual(self.accept()["status"], "accepted")
