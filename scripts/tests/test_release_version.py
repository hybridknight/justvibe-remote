import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_release', Path(__file__).parents[1] / 'check-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseVersionTests(unittest.TestCase):
    def fixture(self, root, windows='1.0.0', manifest='1.0.0.0'):
        (root / 'macos').mkdir()
        (root / 'macos/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.0'}))
        app = root / 'windows/JustVibeRemote.App'
        app.mkdir(parents=True)
        (app / 'JustVibeRemote.App.csproj').write_text(f'<Project><PropertyGroup><Version>{windows}</Version></PropertyGroup></Project>')
        (app / 'app.manifest').write_text(f'<assembly xmlns="urn:schemas-microsoft-com:asm.v1"><assemblyIdentity version="{manifest}"/></assembly>')

    def test_matching_versions(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            self.assertEqual(release.check_release('v1.0.0', root), '1.0.0')

    def test_rejects_invalid_tags_before_reading_files(self):
        for tag in ['1.0.0', 'v01.0.0', 'v1.0', 'v1.0.0-rc.1', 'v1.0.0\n', 'v1.0.0;echo bad']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.check_release(tag, Path('/missing'))

    def test_rejects_mismatched_metadata(self):
        for windows, manifest in [('0.9.4', '1.0.0.0'), ('1.0.0', '0.1.0.0')]:
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                self.fixture(root, windows, manifest)
                with self.assertRaises(ValueError):
                    release.check_release('v1.0.0', root)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            with self.assertRaisesRegex(ValueError, 'macOS'):
                release.check_release('v1.0.1', root)


if __name__ == '__main__':
    unittest.main()
