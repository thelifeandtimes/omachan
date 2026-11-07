"""An Omabit approval owns one keyring item, addressed by plugin/profile and request."""
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import re
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import urllib.request

from .instance import INSTANCE, account_path, read_object
from .journal import fingerprint, secret_present, sync_directory
from .offer import HandoffError


class ApprovedCookie(urllib.request.BaseHandler):
    """Attach the credential only to the approved origin, including its port."""
    def __init__(self, session):
        self.session = session
        self.expires = datetime.fromisoformat(session["expires"])

    def check_expiry(self):
        if datetime.now(timezone.utc) >= self.expires:
            raise HandoffError("expired")

    def http_request(self, request):
        self.check_expiry()
        session = self.session
        if request.type + "://" + request.host != session["url"]:
            raise HandoffError("wrong-origin")
        request.add_unredirected_header("Cookie", session["cookieName"] + "=" + session["cookieValue"])
        return request

    https_request = http_request


class Store:
    def __init__(self, path=None):
        self.path = Path(path) if path is not None else account_path()
        self.root = self.path.parent / (self.path.name + ".omabit")

    @contextmanager
    def locked(self, name="account"):
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = self.root.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise HandoffError("storage")
        fd = os.open(self.root / (name + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "rb") as lock:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
                raise HandoffError("storage")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise HandoffError("account-busy") from None
            yield

    def account(self):
        try:
            value = read_object(self.path)
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            raise HandoffError("storage") from None
        if not isinstance(value, dict) or not isinstance(value.get("baseUrl"), str) or not isinstance(value.get("ship"), str):
            raise HandoffError("storage")
        if "application_request_id" in value and (
                set(value) != {"baseUrl", "ship", "application_request_id", "fingerprint", "expires"}
                or not all(isinstance(item, str) for item in value.values())
                or not re.fullmatch("[0-9a-f]{32}", value["application_request_id"])
                or not re.fullmatch("[0-9a-f]{64}", value["fingerprint"])):
            raise HandoffError("storage")
        return value

    def secret(self, action, request_id, data=b""):
        args = ["/usr/bin/secret-tool", action]
        if action == "store":
            args.append("--label=" + INSTANCE.label)
        args.extend(["application", INSTANCE.state_name, "request", request_id])
        try:
            result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, timeout=6)
        except (OSError, subprocess.TimeoutExpired):
            raise HandoffError("keyring-unavailable") from None
        if result.returncode or len(result.stdout) > 16384:
            raise HandoffError("keyring-unavailable")
        return result.stdout

    def save(self, offer, session):
        request_id = offer["request_id"]
        account = {"baseUrl": session["url"], "ship": session["ship"][1:],
                   "application_request_id": request_id, "fingerprint": fingerprint(session),
                   "expires": session["expires"]}
        self.secret("store", request_id, json.dumps(session).encode())
        self.session(account)  # Confirm the exact credential before publishing the account.
        fd, temp = tempfile.mkstemp(dir=self.path.parent, prefix=".account-")
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(account, stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp, self.path)
            sync_directory(self.path.parent)
        finally:
            Path(temp).unlink(missing_ok=True)

    def session(self, account):
        raw = self.secret("lookup", account["application_request_id"])
        try:
            session = json.loads(raw)
        except (ValueError, UnicodeError):
            raise HandoffError("account-changed") from None
        if (fingerprint(session) != account["fingerprint"] or session["url"] != account["baseUrl"]
                or session["ship"] != "~" + account["ship"] or session["expires"] != account["expires"]):
            raise HandoffError("account-changed")
        ApprovedCookie(session).check_expiry()
        return session

    def clear_secret(self, request_id, expected):
        if secret_present(INSTANCE, request_id):
            if fingerprint(json.loads(self.secret("lookup", request_id))) != expected:
                raise HandoffError("account-changed")
            self.secret("clear", request_id)
            if secret_present(INSTANCE, request_id):
                raise HandoffError("keyring-unavailable")

    def forget(self, account):
        """Caller holds the account lock; keep the issuer's replay/cleanup records."""
        self.clear_secret(account["application_request_id"], account["fingerprint"])
        self.path.unlink()
        sync_directory(self.path.parent)
