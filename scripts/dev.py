#!/usr/bin/env python3
"""Private HTTP and conn.sock helpers for the three omachan-dev fake ships."""
from __future__ import annotations

import http.cookiejar
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PORTS = {"fex": 8101, "wes": 8102, "sev": 8103, "let": 8104}


def conn(ship, source, dependencies=()):
    socket = Path.home() / "temp-ur/fakeships" / ("fake-" + ship) / ".urb/conn.sock"
    if ship not in PORTS or not socket.is_socket():
        raise RuntimeError(f"Missing local fakeship: {ship}")
    source = source.replace("\\", "\\\\").replace("'", "\\'")
    argument = f"'{source}'"
    if dependencies:
        argument = f"[{argument} ~[{' '.join(dependencies)}]]"
    request = f"[0 %fyrd %base %khan-eval %noun %ted-eval {argument}]\n"

    def run(args, data):
        return subprocess.run(args, input=data, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, check=True, timeout=30).stdout

    jam = run(["urbit", "eval", "-jn"], request.encode())
    answer = run(["nc", "-U", "-W", "30", str(socket)], jam)
    rendered = run(["urbit", "eval", "-cn"], answer).decode().strip()
    if not rendered.startswith("[0 %avow 0 %noun "):
        raise RuntimeError(rendered)
    return rendered


class Ship:
    def __init__(self, ship):
        self.ship = ship
        self.url = f"http://127.0.0.1:{PORTS[ship]}"
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        code = conn(ship, '=/  m  (strand ,vase)  ;<  =bowl:spider  bind:m  get-bowl  '
                    '(pure:m !>((scot %p .^(@p %j /(scot %p our.bowl)/code/'
                    '(scot %da now.bowl)/(scot %p our.bowl)))))')
        password = re.search(r"~[a-z-]+", code)[0][1:]
        self.opener.open(self.url + "/~/login", timeout=15,
                         data=urllib.parse.urlencode({"password": password}).encode()).read()
        assert self.api("state.json")["our"] == "~" + ship

    def api(self, path, body=None):
        req = urllib.request.Request(self.url + "/omachan/" + path,
                                     headers={"content-type": "application/json",
                                              "x-omachan": "1", "Origin": self.url},
                                     data=None if body is None else json.dumps(body).encode())
        with self.opener.open(req, timeout=15) as response:
            return json.load(response)


def wait_for(label, predicate, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.2)
    raise AssertionError(f"Timed out: {label}")
