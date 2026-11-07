"""Local-origin handling and in-memory session behavior; no live ship needed."""
import importlib.util
import io
import os
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('bridge',Path(__file__).resolve().parents[1]/'plugin/bridge.py')
bridge=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)
        scope = patch.dict(os.environ, {"XDG_STATE_HOME": self.state.name})
        scope.start()
        self.addCleanup(scope.stop)
    def test_origin_rejects_credential_or_path_ambiguity(self):
        self.assertEqual(bridge.origin(' ship.example/ '),'https://ship.example')
        self.assertEqual(bridge.origin('http://[::1]:8101'),'http://[::1]:8101')
        self.assertEqual(bridge.origin('http://127.0.0.1:8102'),'http://127.0.0.1:8102')
        for value in ('file:///tmp/test','http://user:secret@ship.example','http://ship.example/path','http://ship.example?redirect=evil','http://ship.example:0','http://ship.example\n.evil','http://remote.example','http://192.168.1.4'):
            with self.subTest(value=value),self.assertRaises(ValueError): bridge.origin(value)

    def test_redirects_are_not_followed(self):
        self.assertIsNone(bridge.NoRedirect().redirect_request(None,None,302,'',{},'https://elsewhere.invalid'))

    def test_ship_reads_identify_the_omachan_client(self):
        client = bridge.Client()
        client.url = 'https://ship.example'
        with patch.object(client.opener, 'open', return_value=io.BytesIO(b'{}')) as send:
            self.assertEqual(client.pikes(), {})
        self.assertEqual(send.call_args.args[0].get_header('User-agent'), 'Omachan/0.4')

    def test_failed_login_drops_session(self):
        c=bridge.Client()
        with patch.object(c,'request',side_effect=ValueError('rejected')):
            with self.assertRaises(ValueError): c.login('http://localhost:8101','fake-code')
        self.assertEqual(c.url,'')
        self.assertEqual(len(c.cookies),0)

    def test_login_does_not_echo_server_reflection_of_code(self):
        c=bridge.Client()
        with patch.object(c,'request',side_effect=ValueError('Rejected SECRET')):
            with self.assertRaises(ValueError) as error: c.login('https://ship.example','SECRET')
        self.assertNotIn('SECRET',str(error.exception))

    def test_forbidden_action_preserves_a_still_authenticated_account(self):
        client = bridge.Client()
        client.ship = "~wes"
        client.url = "https://ship.example"
        denied = bridge.urllib.error.HTTPError(client.url, 403, "denied", {}, None)
        with patch.object(client.opener, "open", side_effect=[denied, io.BytesIO(b"~wes")]):
            with self.assertRaisesRegex(bridge.HttpFailure, "declined"):
                client.act({"action": "post", "text": "fixture"})
        self.assertEqual(client.ship, "~wes")

    def test_expired_cookie_clears_account(self):
        c=bridge.Client(); c.url='https://ship.example'
        with patch.object(c.opener,'open',side_effect=bridge.urllib.error.HTTPError(c.url,401,'expired',{},None)):
            with self.assertRaises(ValueError): c.state()
        self.assertEqual(c.url,'')

    def test_json_lines_do_not_echo_credentials(self):
        with patch.object(bridge.sys,'stdin',io.StringIO('{"action":"login","url":"https://ship.example","code":"SECRET","request":7}\n')),patch.object(bridge.sys,'stdout',new_callable=io.StringIO) as out,patch.object(bridge.Client,'login',side_effect=ValueError('rejected')):
            bridge.main()
            self.assertNotIn('SECRET',out.getvalue())
            self.assertIn('"request": 7',out.getvalue())

    def test_missing_app_preserves_authenticated_session(self):
        c=bridge.Client(); c.url='https://ship.example'; c.ship='~wes'
        with patch.object(c,'request',side_effect=bridge.HttpFailure(404,'Missing')), patch.object(c,'pikes',return_value={'base':{'zest':'live'}}):
            state=c.state()
        self.assertFalse(state['available'])
        self.assertEqual(c.url,'https://ship.example')

    def test_server_error_does_not_offer_install(self):
        c=bridge.Client(); c.url='https://ship.example'; c.app_seen=True
        with patch.object(c,'request',side_effect=bridge.HttpFailure(503,'Unavailable')):
            with self.assertRaises(bridge.HttpFailure): c.state()

    def test_install_keeps_existing_pals_source(self):
        c=bridge.Client(); c.url='https://ship.example'; c.ship='~wes'
        with patch.object(c,'pikes',return_value={'pals':{'zest':'live','sync':{'ship':'~paldev'}}}), patch.object(c,'poke') as poke, patch.object(c,'state',return_value={}):
            c.install('~fex')
            poke.assert_called_once_with('kiln-install',{'local':'omachan','ship':'~fex','desk':'omachan'})

    def test_install_includes_only_required_desks_and_revives_suspended(self):
        c=bridge.Client(); c.url='https://ship.example'; c.ship='~wes'
        with patch.object(c,'pikes',return_value={'omachan':{'zest':'held'}}), patch.object(c,'poke') as poke, patch.object(c,'state',return_value={}):
            c.install('~fex')
            self.assertEqual(poke.call_args_list, [unittest.mock.call('kiln-install',{'local':'pals','ship':'~fex','desk':'pals'}), unittest.mock.call('kiln-revive','omachan')])

    def test_install_revives_existing_dead_desk_without_changing_source(self):
        c=bridge.Client(); c.url='https://ship.example'; c.ship='~wes'
        with patch.object(c,'pikes',return_value={'pals':{'zest':'dead','sync':{'ship':'~paldev'}},'omachan':{'zest':'live'}}), patch.object(c,'poke') as poke, patch.object(c,'state',return_value={}):
            c.install('~fex')
            poke.assert_called_once_with('kiln-revive','pals')

    def test_first_install_defaults_to_release_distributor(self):
        c=bridge.Client(); c.ship='~wes'
        state=c.setup_state({'base':{'zest':'live'}})
        self.assertEqual(state['distributor'],'~dister-dozzod-sarlev')
        self.assertIsNone(state['hub'])

    def test_install_source_never_overwrites_desks_hub(self):
        c=bridge.Client(); c.url='https://ship.example'; c.app_seen=True
        c.distributor='~dister-dozzod-sarlev'
        payload={'peers':[],'posts':[],'hub':'~sogryp-hoster-dozzod-sarlev','seed':'~sogryp-hoster-dozzod-sarlev'}
        with patch.object(c,'request',return_value=bridge.json.dumps(payload).encode()):
            state=c.state()
        self.assertEqual(state['hub'],'~sogryp-hoster-dozzod-sarlev')
        self.assertEqual(state['seed'],state['hub'])

    def test_install_rejects_path_and_self(self):
        c=bridge.Client(); c.ship='~wes'
        for ship in ('~wes','~fex/other','fex','~fex?desk=base',''):
            with self.subTest(ship=ship),self.assertRaises(ValueError): c.install(ship)


if __name__=='__main__': unittest.main()
