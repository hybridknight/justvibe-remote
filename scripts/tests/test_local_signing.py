import contextlib
import importlib.util
import io
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('local_signing',Path(__file__).parents[1]/'local-signing.py')
signing=importlib.util.module_from_spec(spec);spec.loader.exec_module(signing)

class SigningSafetyTests(unittest.TestCase):
    def test_timeout_does_not_expose_command_credentials(self):
        with patch.object(signing.subprocess,'run',side_effect=subprocess.TimeoutExpired(['security','-p','private-test-secret'],1)):
            with self.assertRaises(RuntimeError) as result:signing.run(['security','-p','private-test-secret'],'private-test-secret')
        self.assertNotIn('private-test-secret',str(result.exception))

    def test_existing_identity_is_not_regenerated(self):
        with tempfile.TemporaryDirectory() as folder:
            config=Path(folder)/'identity.json';config.write_text('{"fingerprint":"saved"}')
            with patch.object(signing,'CONFIG',config),patch.object(signing,'run') as native,contextlib.redirect_stdout(io.StringIO()):signing.setup()
            native.assert_not_called();self.assertEqual(config.read_text(),'{"fingerprint":"saved"}')

    def test_missing_identity_never_falls_back_to_adhoc(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(signing,'CONFIG',Path(folder)/'missing'),patch.object(signing,'run') as native:
                with self.assertRaisesRegex(RuntimeError,'No ad-hoc fallback'):signing.sign('/tmp/app')
            native.assert_not_called()

    def test_search_list_cleanup_preserves_concurrent_entries(self):
        commands=[];queries=iter(['"login.keychain-db"','"login.keychain-db" "ours.keychain-db" "another.keychain-db"'])
        def native(args,*unused):
            commands.append(args)
            return next(queries) if args==['/usr/bin/security','list-keychains','-d','user'] else ''
        with patch.object(signing,'run',side_effect=native):
            with self.assertRaisesRegex(RuntimeError,'test failure'):
                with signing.searchable('ours.keychain-db'):raise RuntimeError('test failure')
        self.assertEqual(commands[-1],['/usr/bin/security','list-keychains','-d','user','-s','login.keychain-db','another.keychain-db'])

    def test_existing_search_list_membership_is_left_intact(self):
        commands=[]
        def native(args,*unused):commands.append(args);return '"login.keychain-db" "ours.keychain-db"'
        with patch.object(signing,'run',side_effect=native):
            with signing.searchable('ours.keychain-db'):pass
        self.assertEqual(commands,[['/usr/bin/security','list-keychains','-d','user']])

    @unittest.skipUnless(shutil.which('zsh'), 'macOS build script requires zsh')
    def test_failed_build_signing_preserves_installed_app(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'scripts').mkdir();(root/'macos/Sources').mkdir(parents=True);(root/'plugins/bundled').mkdir(parents=True);(root/'bin').mkdir()
            shutil.copy(Path(__file__).parents[1]/'build-macos.sh',root/'scripts/build-macos.sh')
            (root/'macos/Info.plist').write_text('fixture');(root/'macos/Sources/main.swift').write_text('fixture')
            (root/'assets/branding').mkdir(parents=True)
            for asset in ['JustVibeRemote.icns','JustVibeRemote.png']:(root/'assets/branding'/asset).write_text('fixture')
            (root/'plugins/examples/device').mkdir(parents=True)
            (root/'docs').mkdir()
            for guide in ['PLUGIN-AUTHORING.md','PLUGINS.md','IMAGE-TO-PLUGIN.md']:(root/'docs'/guide).write_text('fixture')
            installed=root/'dist/JustVibe Remote.app';(installed/'Contents/MacOS').mkdir(parents=True);(installed/'Contents/MacOS/JustVibeRemote').write_text('last working app')
            (root/'bin/xcrun').write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "-o" ]; then shift; printf new > "$1"; exit 0; fi; shift; done; exit 1\n')
            (root/'bin/codesign').write_text('#!/bin/sh\nprintf attempted > "$(dirname "$0")/sign-attempted"\nexit 1\n')
            for stub in (root/'bin').iterdir():stub.chmod(0o700)
            env=dict(os.environ,PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],JUSTVIBEREMOTE_SIGNING_IDENTITY='failure-test')
            result=subprocess.run(['zsh',str(root/'scripts/build-macos.sh')],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertTrue((root/'bin/sign-attempted').exists(), 'fixture must reach the signing step')
            self.assertEqual((installed/'Contents/MacOS/JustVibeRemote').read_text(),'last working app')
            self.assertEqual(list((root/'build').glob('macos-stage.*')),[])

    def test_sign_failure_locks_dedicated_keychain(self):
        with tempfile.TemporaryDirectory() as folder:
            config=Path(folder)/'identity.json';config.write_text(json.dumps({'keychain':'dedicated.keychain-db','password':'private-test-secret','fingerprint':'known-signer'}))
            def native(args,*unused):
                if args[0]=='/usr/bin/codesign':raise RuntimeError('signing failed')
                return ''
            with patch.object(signing,'CONFIG',config),patch.object(signing,'run',side_effect=native),patch.object(signing.subprocess,'run') as lock:
                with self.assertRaisesRegex(RuntimeError,'signing failed'):signing.sign('/tmp/app')
                lock.assert_called_once_with(['/usr/bin/security','lock-keychain','dedicated.keychain-db'],capture_output=True)

if __name__=='__main__':unittest.main()
