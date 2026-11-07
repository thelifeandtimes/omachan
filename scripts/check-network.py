#!/usr/bin/env python3
"""Exercise ONLY omachan-dev's fex/wes/sev. Leaves a usable demo graph.

Changes their discovery settings and mutual tags. Test posts remain in these
throwaway piers for 14 days. Never points at an arbitrary or live ship.
"""
import datetime
import re
from pathlib import Path
import time
import urllib.error
import urllib.request
import uuid
from dev import Ship, conn, wait_for, PORTS


def hoon(source):
    """Tall rune arguments need gaps; wide expressions retain single spaces."""
    out, depth, quoted = [], 0, False
    for char in source:
        if char == "'": quoted = not quoted
        if not quoted:
            if char in '([': depth += 1
            elif char in ')]': depth -= 1
        out.append('  ' if char.isspace() and depth == 0 and not quoted else char)
    return ''.join(out)


def evaluate(ship, source, *imports):
    when = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=1)).strftime('~%Y.%m.%d..%H.%M.%S')
    deps = [f"['~{ship}' %omachan '{when}' %{kind} %{name} %hoon ~]" for kind, name in imports]
    return conn(ship, hoon(source), deps)


def pals(ship, peer, command, tags='~'):
    return conn(ship, hoon(f"=/ m (strand ,vase) ;< ~ bind:m (poke [~{ship} %pals] %pals-command !>([%{command} ~{peer} {tags}])) (pure:m !>(%ok))"))


def claim(ship, owner):
    result = evaluate(ship, f"=/ m (strand ,vase) ;< st=state bind:m (scry state /gx/omachan/raw/noun) =/ a (~(got by claims.st) ~{owner}) (pure:m !>(`@ux`(jam data.a)))", ('sur','omachan'))
    digits = re.search(r'0x[0-9a-f.]+', result)[0][2:].replace('.', '')
    groups = [digits[max(0,i-4):i] for i in range(len(digits),0,-4)]
    return '0x' + '.'.join(reversed(groups))


def send_claim(via, to, atom, tamper=False):
    change = '=. c c(signature +(signature.c)) ' if tamper else ''
    return evaluate(via, f"=/ m (strand ,vase) =/ c ;;(claim (cue {atom})) {change};< ~ bind:m (poke [~{to} %omachan] %omachan-claims !>(`(list claim-wire)`[[c 2] ~])) (pure:m !>(%ok))", ('sur','omachan'))


def send_pass(via, to, text, reject=False):
    source = f"=/ m (strand ,vase) ;< b=bowl:spider bind:m get-bowl =/ p=post [(sham [now.b eny.b '{text}']) now.b '{text}'] ;< ~ bind:m (poke [~{to} %omachan] %omachan-pass !>(p)) (pure:m !>(%ok))"
    try:
        evaluate(via, source, ('sur', 'omachan'))
    except RuntimeError as error:
        if reject and '%poke-fail' in str(error): return
        raise
    assert not reject, 'Unauthorized private handoff was accepted'


def check_crypto():
    source = '''=/ m (strand ,vase) ;< =bowl:spider bind:m get-bowl
    =/ c (seal our.bowl now.bowl 1 & |)
    ?> =(`& (authenticate our.bowl now.bowl c))
    ?> !(autograph c(signature +(signature.c)))
    ?> =(`| (authenticate our.bowl now.bowl c(body body.c(origin ~sev))))
    ?> !(fresh now.bowl c(body body.c(issued (sub now.bowl ~d8), expires (sub now.bowl ~d1))))
    ?> !(fresh now.bowl c(body body.c(issued (add now.bowl ~m6))))
    ?> !(newer c c)
    ?> (newer c(body body.c(active |)) c)
    =/ initial *state
    ?> !joined.initial
    ?> !relay-only.cfg.initial
    (pure:m !>(%ok))'''
    # Imported cores are placed directly in the thread subject.
    evaluate('wes', ' '.join(source.split()), ('lib','omachan-crypto'))
    print('PASS: signatures, forged identity, expiry, future clock, replay ordering, opt-in defaults', flush=True)


def check_board():
    source = (Path(__file__).resolve().parents[1] / 'tests/board.hoon').read_text()
    source = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('::'))
    evaluate('sev', source, ('lib', 'omachan-board'), ('lib', 'omachan-network'))
    print('PASS: controlled origin/proxy coin flips, private snapshots, ack/nack/timeout, stale events, hop budget, deduplication, reload and eligibility cleanup', flush=True)


def check_missing_pals():
    s=Ship('wes')
    try:
        conn('wes',hoon('=/ m (strand ,vase) ;< ~ bind:m (poke [~wes %hood] %kiln-suspend !>(%pals)) (pure:m !>(%ok))'))
        wait_for('Pals suspended',lambda: not s.api('state.json')['palsRunning'])
        assert not any(p['eligible'] for p in s.api('state.json')['peers'])
        try: s.api('action',{'action':'post','text':'must not publish without pals'})
        except urllib.error.HTTPError as e: assert e.code==400
        else: raise AssertionError('Posting succeeded without %pals')
        print('PASS: missing Pals closes peer eligibility and rejects publishing',flush=True)
    finally:
        conn('wes',hoon('=/ m (strand ,vase) ;< ~ bind:m (poke [~wes %hood] %kiln-revive !>(%pals)) (pure:m !>(%ok))'))
        wait_for('Pals resumed',lambda: s.api('state.json')['palsRunning'])
        s.api('action',{'action':'retry'})


def main():
    ships = {n: Ship(n) for n in ('fex', 'wes', 'sev')}
    fex, wes, sev = (ships[n] for n in ships)
    prefix = 'check-' + uuid.uuid4().hex[:8]
    def state(s): return s.api('state.json')
    def act(s, action, **fields): return s.api('action', {'action':action, **fields})
    def peer(s, name): return next((p for p in state(s)['peers'] if p['ship']=='~'+name), {})
    def has(s, text): return any(p['text']==text for p in state(s)['posts'])
    def post(s, suffix):
        text = prefix + '-' + suffix
        act(s, 'post', text=text)
        return text
    def retry():
        for s in ships.values(): act(s, 'retry')
    def config(s, seed=''): act(s, 'config', seed=seed)
    def expect_http(code, fn):
        try: fn()
        except urllib.error.HTTPError as e: assert e.code == code, (e.code, code)
        else: raise AssertionError('Expected HTTP '+str(code))

    try:
        for n,s in ships.items():
            act(s,'preferences',autoAccept=False)
            act(s,'leave')
            config(s, '' if n=='fex' else '~fex')
            pals(n,'paldev','part')
            for other in ships:
                if n != other:
                    pals(n,other,'part')
                    act(s,'restore',ship='~'+other)
        wait_for('Pals edges cleared',lambda: all(not any(p['target'] or p['incoming'] for p in state(s)['peers']) for s in ships.values()))
        for s in ships.values(): act(s,'join')
        wait_for('all signed claims',lambda: all(sum(p['active'] for p in state(s)['peers'])==2 for s in ships.values()))
        assert all(not p['target'] and not p['tagged'] for s in ships.values() for p in state(s)['peers'])
        print('PASS: explicit discovery works without creating any Pals relationships', flush=True)
        check_crypto()

        active = claim('fex','wes')
        act(wes,'leave')
        wait_for('withdrawal relayed',lambda: not peer(sev,'wes')['active'])
        send_claim('fex','sev',active)
        time.sleep(.5)
        assert not peer(sev,'wes')['active'], 'replay resurrected a withdrawn claim'
        act(wes,'join')
        wait_for('new announcement',lambda: peer(sev,'wes')['active'])
        current = claim('fex','wes')
        send_claim('fex','sev',current,tamper=True)
        assert claim('sev','wes') == current
        print('PASS: signed withdrawal wins over replay; damaged signatures cannot replace claims', flush=True)

        # Existing friendship tags must survive the explicit discovery action.
        pals('wes','sev','meet','(silt ~[~.existing])')
        act(wes,'add',ship='~sev')
        assert not peer(wes,'sev')['connected']
        early=post(wes,'before-add-back')
        time.sleep(.5)
        assert not has(sev,early)
        act(sev,'add',ship='~wes')
        retry()
        wait_for('reciprocal connection',lambda: peer(wes,'sev')['connected'] and peer(sev,'wes')['connected'])
        wait_for('catch-up',lambda: has(sev,early))
        live=post(sev,'live'); wait_for('live delivery',lambda: has(wes,live))
        assert not has(fex,early) and not has(fex,live)
        private = prefix + '-private-handoff'
        send_pass('wes', 'sev', private)
        wait_for('private handoff broadcast', lambda: has(sev,private) and has(wes,private))
        assert not has(fex,private)
        print('PASS: manual add-back, cached catch-up, live posts, private handoffs, and no board delivery to untagged bootstrap', flush=True)

        # %pals emits no event for a tag-only edit. Both send and receive guards
        # must therefore read its current state on every board message.
        pals('wes','sev','part','(silt ~[~.omarchy])')
        assert peer(wes,'sev')['target'] and not peer(wes,'sev')['tagged']
        blocked=post(sev,'tag-removed-receive')
        blocked2=post(wes,'tag-removed-send')
        time.sleep(.5)
        assert not has(wes,blocked) and not has(sev,blocked2)
        private_blocked = prefix + '-private-untagged'
        send_pass('sev', 'wes', private_blocked, reject=True)
        assert not has(wes, private_blocked)
        existing=conn('wes',hoon('=/ m (strand ,vase) ;< yes=? bind:m (scry ? /gx/pals/targets/existing/~sev/noun) (pure:m !>(yes))'))
        assert existing.endswith('%noun 0]')
        act(wes,'add',ship='~sev'); retry()
        wait_for('tag restored',lambda: peer(wes,'sev')['connected'] and peer(sev,'wes')['connected'])
        print('PASS: removing only the tag immediately blocks both directions and preserves other tags', flush=True)

        # A fresh wes claim must reach fex through ordinary sev, despite both
        # ends declining a direct discovery connection to each other.
        config(wes,'~sev')
        act(wes,'dismiss',ship='~fex'); act(fex,'dismiss',ship='~wes')
        act(wes,'join'); retry()
        wait_for('ordinary peer discovery relay',lambda: peer(fex,'wes')['via']=='~sev' and peer(fex,'wes')['hop']==2)
        print('PASS: discovery relays through an ordinary participant without a central registrar', flush=True)

        # Temporarily use all three as board participants: wes--sev--fex.
        for s in ships.values(): config(s)
        for s in ships.values():
            for n in ships:
                if n!=s.ship: act(s,'restore',ship='~'+n)
        retry()
        act(sev,'add',ship='~fex'); act(fex,'add',ship='~sev'); retry()
        wait_for('chain connected',lambda: peer(fex,'sev')['connected'] and peer(sev,'fex')['connected'])
        check_board()
        two=post(wes,'two-hop'); wait_for('two-hop delivery',lambda: has(fex,two))
        distance=evaluate('fex', f"=/ m (strand ,vase) ;< st=state bind:m (scry state /gx/omachan/raw/noun) (pure:m !>((turn (skim ~(val by posts.st) |=(p=post-entry =(what.data.p '{two}'))) |=(p=post-entry distance.p))))", ('sur','omachan'))
        assert any(distance.endswith(f'%noun {d} 0]') for d in (0,1,2)), distance
        atom_before=claim('sev','wes')
        retry(); time.sleep(.5)
        assert sum(p['text']==two for p in state(fex)['posts'])==1
        assert claim('sev','wes')==atom_before
        print('PASS: chain delivery with randomized passes and deduplicated reconnect gossip', flush=True)
        # A configured first contact follows the same board rules as any pal.
        config(sev, '~fex'); config(fex, '~sev'); retry()
        wait_for('bootstrap mutual connection', lambda: peer(sev,'fex')['connected'] and peer(fex,'sev')['connected'])
        ordinary = prefix + '-bootstrap-private'
        send_pass('sev', 'fex', ordinary)
        wait_for('bootstrap receives private gossip', lambda: has(fex,ordinary))
        announced = post(fex, 'bootstrap-publishes')
        wait_for('bootstrap publishes normally', lambda: has(sev,announced))
        act(fex,'config',seed='~sev',relayOnly=True)
        assert 'relayOnly' not in state(fex)
        legacy = post(fex, 'legacy-role-is-inert')
        wait_for('obsolete role cannot block publishing', lambda: has(sev,legacy))
        print('PASS: bootstrap receives, relays and publishes as an ordinary tagged peer; legacy role is inert', flush=True)

        expect_http(401,lambda: urllib.request.urlopen(wes.url+'/omachan/state.json'))
        expect_http(403,lambda: wes.opener.open(urllib.request.Request(wes.url+'/omachan/action',data=b'{"action":"leave"}',headers={'Content-Type':'application/json','x-omachan':'1','Origin':'https://elsewhere.invalid'})))
        expect_http(400,lambda: act(wes,'post',text='x'*1025))
        print('PASS: private state, same-origin writes, and content-size enforcement', flush=True)
        check_missing_pals()
    finally:
        for n,s in ships.items():
            for other in ships:
                if n!=other: act(s,'restore',ship='~'+other)
            config(s,'' if n=='fex' else '~fex')
            act(s,'join')
        # Leave an all-to-all test neighborhood. Every ship is an equal peer.
        for n,s in ships.items():
            for other in ships:
                if n != other: act(s,'add',ship='~'+other)
        retry()
        print('Demo restored: ~fex, ~wes and ~sev are tagged mutuals; ~fex is the default first contact. Test history remains.', flush=True)


if __name__=='__main__': main()
