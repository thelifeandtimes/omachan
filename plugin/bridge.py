#!/usr/bin/env python3
"""Single-account Eyre client for standalone and Omabit-approved sign-in.

The bar widget keeps this process alive between popup opens. Standalone sessions stay in memory. Approved sessions use Secret Service. Explicit URLs are never followed to a
new origin through a redirect.
"""
from __future__ import annotations
import http.cookiejar
import ipaddress
import json
from pathlib import Path
import sys
import contextlib
import re
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request


# Also support loading this bridge by filename in the offline test harness.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_connection.offer import HandoffError
from app_connection.store import ApprovedCookie, Store


DEFAULT_DISTRIBUTOR = '~dister-dozzod-sarlev'


def origin(value: str) -> str:
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError('Enter a ship URL')
    value = value.strip().rstrip('/')
    if '://' not in value:
        value = 'https://' + value
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname or
            parsed.username or parsed.password or parsed.path or parsed.query or
            parsed.fragment or parsed.port == 0 or any(ord(c) < 33 for c in value)):
        raise ValueError('Enter a ship URL without a path or credentials')
    try:
        loopback = ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:
        loopback = parsed.hostname.lower().rstrip('.') == 'localhost'
    if parsed.scheme == 'http' and not loopback:
        raise ValueError('Use HTTPS for a remote ship. HTTP is supported for local fake ships.')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class HttpFailure(ValueError):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


class Client:
    def __init__(self, store=None):
        self.store = store or Store()
        self.direct_lease = contextlib.ExitStack()
        self.rejected_request = None
        self.logout()

    def logout(self):
        self.direct_lease.close()
        self.binding = ""
        self.url = ''
        self.ship = ''
        self.distributor = ''
        self.install_requested = False
        self.app_seen = False
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(self.cookies))

    def sign_out(self):
        if self.binding and self.binding != "direct":
            with self.store.locked():
                account = self.store.account()
                if account and account.get("application_request_id") == self.binding:
                    self.store.forget(account)
        self.logout()

    def check_current(self):
        if self.binding and self.binding != "direct":
            account = self.store.account()
            if not account or account.get("application_request_id") != self.binding:
                self.logout()
                raise ValueError("The Omabit connection changed. Refresh to load the current account.")

    def restore(self):
        if not self.url:
            account = self.store.account()
            if account is None:
                return None
            with self.store.locked():
                account = self.store.account()
                if account is None:
                    return None
                request_id = account["application_request_id"]
                if request_id == self.rejected_request:
                    raise ValueError("Session rejected by Eyre. Disconnect in Omabit and approve a new connection.")
                session = self.store.session(account)
                cookie = ApprovedCookie(session)
                self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(), cookie)
                self.binding = request_id
                self.url = session["url"]
                self.ship = session["ship"]
        return self.state()

    def request(self, path, body=None, form=False, method=None, stream=False):
        self.check_current()
        if not self.url:
            raise ValueError('Sign in to your ship first')
        data = None if body is None else (urllib.parse.urlencode(body).encode() if form else json.dumps(body).encode())
        headers = {'User-Agent': 'Omachan/0.4', 'Origin': self.url, 'x-omachan': '1', 'Accept': 'text/event-stream' if stream else 'application/json',
                   'Content-Type': 'application/x-www-form-urlencoded' if form else 'application/json'}
        req = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            response = self.opener.open(req, timeout=12)
            if stream:
                return response
            with response:
                result = response.read(2_000_001)
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                error.close()
                if error.code == 403 and path == "/omachan/action":
                    # A desk-level denial is distinct from an expired Eyre session.
                    if self.request("/~/name").strip() == self.ship.encode():
                        raise HttpFailure(403, "Your ship declined this Omachan action.") from None
                self.rejected_request = self.binding
                self.logout()
                raise ValueError('Sign-in expired or was rejected. Sign in again.') from None
            if 300 <= error.code < 400:
                error.close()
                raise ValueError('The ship redirected this request. Use its direct URL.') from None
            error.close()
            raise HttpFailure(error.code, "The ship returned HTTP " + str(error.code)) from None
        if len(result) > 2_000_000:
            raise ValueError('The ship response was too large')
        self.check_current()
        return result

    def setup_state(self, pikes):
        installed = pikes.get('omachan', {}).get('zest') not in (None, 'dead')
        return dict(our=self.ship, available=False, installed=installed,
                    installing=self.install_requested, distributor=self.distributor or (pikes.get('omachan', {}).get('sync') or {}).get('ship') or DEFAULT_DISTRIBUTOR, hub=None,
                    peers=[], posts=[], palsRunning=pikes.get('pals', {}).get('zest') == 'live',
                    note='Waiting for installation. Check again shortly.' if self.install_requested else '')

    def state(self):
        if not self.app_seen:
            pikes = self.pikes()
            if pikes.get('omachan', {}).get('zest') != 'live':
                return self.setup_state(pikes)
        try:
            data = json.loads(self.request('/omachan/state.json'))
        except HttpFailure as error:
            if error.status != 404:
                raise
            self.app_seen = False
            return self.setup_state(self.pikes())
        except json.JSONDecodeError:
            raise ValueError('The ship returned an invalid Omachan response') from None
        if not isinstance(data, dict) or not isinstance(data.get('peers'), list) or not isinstance(data.get('posts'), list):
            raise ValueError('The ship returned an invalid Omachan response')
        self.app_seen = True
        data['available'] = True
        data['installed'] = True
        return data

    def login(self, url, code):
        self.logout()
        url = origin(url)
        if not isinstance(code, str) or not code.strip() or len(code) > 512:
            self.logout()
            raise ValueError('Enter the +code from your ship')
        try:
            self.direct_lease.enter_context(self.store.locked("direct"))
            if self.store.account() is not None:
                raise ValueError("Disconnect the existing Omabit session before using direct credentials.")
        except Exception:
            self.logout()
            raise
        self.url = url
        self.binding = "direct"
        try:
            self.request('/~/login', {'password': code.strip().removeprefix('~')}, form=True)
        except Exception:
            self.logout()
            # Never surface a server response that might echo the supplied code.
            raise ValueError('Sign-in failed. Check the ship URL and +code.') from None
        try:
            names = [c.name.removeprefix('urbauth-') for c in self.cookies if c.name.startswith('urbauth-~')]
            if len(names) != 1 or not re.fullmatch(r'~[a-z]+(?:-+[a-z]+)*', names[0]):
                raise ValueError('The ship did not return a valid session')
            self.ship = names[0]
            return self.state()
        except Exception:
            self.logout()
            raise

    def pikes(self):
        data = json.loads(self.request('/~/scry/hood/kiln/pikes.json'))
        if not isinstance(data, dict):
            raise ValueError('Could not read installed desks')
        return data

    def poke(self, mark, value):
        """Wait for the Hood ACK, then close the temporary Eyre channel."""
        path = '/~/channel/omachan-' + uuid.uuid4().hex
        try:
            self.request(path, [dict(id=1, action='poke', ship=self.ship.removeprefix('~'),
                                    app='hood', mark=mark, json=value)], method='PUT')
            with self.request(path, stream=True) as response:
                if response.headers.get_content_type() != 'text/event-stream':
                    raise ValueError('The ship did not return an event stream')
                deadline = time.monotonic() + 15
                data, total = [], 0
                while time.monotonic() < deadline:
                    line = response.readline(65_537)
                    total += len(line)
                    if total > 262_144 or len(line) > 65_536:
                        raise ValueError('Installation response was too large')
                    if not line:
                        break
                    line = line.rstrip(b'\r\n')
                    if line.startswith(b'data:'):
                        data.append(line[5:].lstrip())
                    elif not line and data:
                        event = json.loads(b'\n'.join(data))
                        data = []
                        if type(event.get('id')) is int and event['id'] == 1 and event.get('response') == 'poke':
                            if event.get('err') is not None or event.get('ok') != 'ok':
                                raise ValueError('The ship rejected the installation request')
                            return
                raise ValueError('Installation acknowledgement timed out. Check status before retrying.')
        finally:
            with contextlib.suppress(ValueError, OSError, urllib.error.URLError):
                self.request(path, [dict(id=2, action='delete')], method='PUT')

    def install(self, distributor):
        if not isinstance(distributor, str) or not re.fullmatch(r'~[a-z]+(?:-+[a-z]+)*', distributor) or len(distributor) > 128:
            raise ValueError('Enter a distributor ship such as ~your-distributor')
        if distributor == self.ship:
            raise ValueError('Choose the ship distributing Omachan')
        pikes = self.pikes()
        # Do not replace an existing desk's source. Restore suspended desks,
        # install only absent desks, and let Clay perform its normal validation.
        for desk in ('pals', 'omachan'):
            zest = pikes.get(desk, {}).get('zest')
            if desk not in pikes:
                self.poke('kiln-install', dict(local=desk, ship=distributor, desk=desk))
            elif zest != 'live':
                self.poke('kiln-revive', desk)
        self.distributor = distributor
        self.install_requested = True
        return self.state()

    def act(self, fields):
        allowed = {'join','leave','config','retry','add','remove','dismiss','restore','post','preferences','bootstrap'}
        if fields.get('action') not in allowed:
            raise ValueError('Unknown action')
        return json.loads(self.request('/omachan/action', fields))


def main():
    client = Client()
    for line in sys.stdin:
        ident = None
        try:
            if len(line) > 16_384:
                raise ValueError('Command too large')
            command = json.loads(line)
            if not isinstance(command, dict):
                raise ValueError('Invalid command')
            ident = command.get('request')
            action = command.get('action')
            if action not in ('login', 'restore'):
                if command.get('binding', client.binding) != client.binding:
                    raise ValueError('The selected account changed. Refresh before trying again.')
                client.check_current()
            if action == 'restore':
                state = client.restore()
            elif action == 'login':
                state = client.login(command.get('url', ''), command.get('code', ''))
            elif action == 'logout':
                client.sign_out()
                state = None
            elif action == 'install':
                state = client.install(command.get('ship', ''))
            elif action == 'refresh':
                state = client.state()
            else:
                state = client.act({k:v for k,v in command.items() if k not in ('request', 'binding')})
            result = {'request':ident,'ok':True,'state':state,'url':client.url, 'binding':client.binding}
        except HandoffError as error:
            messages = {
                "expired": "The approved session expired. Disconnect it in Omabit and approve a new connection.",
                "account-busy": "Another connection operation is running. Try again.",
                "keyring-unavailable": "Unlock your desktop keyring and reopen Omachan.",
            }
            if str(error) == "expired":
                client.logout()
            result = {'request': ident, 'ok': False, 'error': messages.get(str(error), 'Check Application Connections in Omabit.'), 'signedOut': not client.url}
        except (ValueError, TypeError, KeyError, OSError, urllib.error.URLError) as error:
            result = {'request':ident,'ok':False,'error':str(error),'signedOut':not client.url}
        print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
