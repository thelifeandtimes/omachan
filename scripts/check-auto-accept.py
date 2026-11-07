#!/usr/bin/env python3
"""Exercise optional auto-accept on the four project fakes; leave fex enabled."""
import importlib.util
from pathlib import Path
import re
import json
import urllib.error
from dev import Ship, wait_for, conn

spec = importlib.util.spec_from_file_location('network_checks', Path(__file__).with_name('check-network.py'))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
ships = {name: Ship(name) for name in ('fex', 'wes', 'sev', 'let')}
fex, wes, sev, new = (ships[name] for name in ships)
def act(s, action, **fields): return s.api('action', dict(action=action, **fields))
def state(s): return s.api('state.json')
def peer(s, who): return next((p for p in state(s)['peers'] if p['ship'] == '~' + who), {})

try:
    act(fex, 'preferences', autoAccept=True)
    wait_for('distributor automatically adds new claimant', lambda: peer(fex, 'let').get('tagged'))
    assert peer(new, 'fex')['tagged']
    print('PASS: the ordinary distributor auto-accepts the explicitly joined client', flush=True)
    act(new, 'preferences', autoAccept=False)
    act(new, 'remove', ship='~wes')
    act(new, 'restore', ship='~wes')
    act(new, 'remove', ship='~sev')
    wait_for('tag removal', lambda: not peer(new, 'wes').get('tagged') and not peer(new, 'sev').get('tagged'))
    n.pals('let', 'wes', 'meet', '(silt ~[~.keep-me])')
    active = n.claim('wes', 'wes')
    act(wes, 'leave')
    wait_for('withdrawal reaches new client', lambda: not peer(new, 'wes').get('active'))
    act(new, 'preferences', autoAccept=True)
    n.send_claim('fex', 'let', active)
    act(new, 'retry')
    assert not peer(new, 'wes')['tagged'], 'Withdrawn/replayed claim auto-accepted'
    assert not peer(new, 'sev')['tagged'], 'Removed/hidden peer auto-accepted'
    print('PASS: withdrawals beat replay and removed peers stay excluded', flush=True)
    act(wes, 'join')
    wait_for('renewed valid claim auto-accepted', lambda: peer(new, 'wes').get('tagged'))
    result = conn('let', n.hoon("=/ m (strand ,vase) ;< tag=? bind:m (scry ? /gx/pals/targets/keep-me/~wes/noun) ?> tag (pure:m !>(%ok))"))
    print('PASS: a new active claim is accepted and existing unrelated Pals tags survive', flush=True)
    atom = n.claim('wes', 'wes')
    n.evaluate('fex', f"=/ m (strand ,vase) =/ c ;;(claim (cue {atom})) =. c c(body body.c(origin ~nec)) ;< ~ bind:m (poke [~let %omachan] %omachan-claims !>(`(list claim-wire)`[[c 2] ~])) (pure:m !>(%ok))", ('sur', 'omachan'))
    act(new, 'retry')
    assert not peer(new, 'nec').get('tagged') and not peer(new, 'nec').get('active')
    print('PASS: a forged ship identity cannot become an auto-accepted pal', flush=True)
    def lifecycle(mark):
        conn('let', n.hoon(f"=/ m (strand ,vase) ;< ~ bind:m (poke [~let %hood] %{mark} !>(%omachan)) (pure:m !>(%ok))"))
    def stopped():
        with new.opener.open(new.url + '/~/scry/hood/kiln/pikes.json', timeout=10) as response:
            return json.load(response)['omachan']['zest'] == 'dead'
    def resumed():
        try: return state(new).get('autoAccept') is True
        except urllib.error.HTTPError as error:
            if error.code in (404, 503): return False
            raise
    try:
        lifecycle('kiln-suspend')
        wait_for('agent stopped', stopped)
    finally:
        lifecycle('kiln-revive')
        wait_for('agent resumed', resumed)
    assert state(new)['preferencesSet']
    assert peer(new, 'sev')['ignored'] and not peer(new, 'sev')['tagged']
    print('PASS: auto-accept, the choice, and exclusions persist across agent restart', flush=True)
finally:
    act(wes, 'join')
    act(fex, 'preferences', autoAccept=True)
    act(new, 'restore', ship='~sev')
    act(new, 'preferences', autoAccept=True)
    n.pals('let', 'wes', 'part', '(silt ~[~.keep-me])')
    print('Demo: fex and let auto-accept; wes and sev retain manual control.', flush=True)
