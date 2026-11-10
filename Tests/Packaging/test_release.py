import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
MOCK_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TEST_TRACE'], 'a') as trace:
    trace.write(json.dumps([name] + args) + '\n')
if name == 'codesign' and '-dv' in args:
    signature = os.environ.get('TEST_APP_SIGNATURE', 'adhoc')
    print(f'Signature={signature}\nTeamIdentifier=not set', file=sys.stderr)
elif name == 'xcrun' and args[0] == '--find':
    print('/mock/' + args[1])
elif name == 'hdiutil' and args[0] == 'create':
    image_root = pathlib.Path(args[args.index('-srcfolder') + 1])
    payload = sorted(path.name for path in image_root.iterdir())
    assert (image_root / 'Applications').is_symlink()
    assert os.readlink(image_root / 'Applications') == '/Applications'
    pathlib.Path(args[-1]).write_text(json.dumps(payload))
elif name == 'hdiutil' and args[0] == 'verify':
    sys.exit(int(os.environ.get('TEST_IMAGE_VERIFY_EXIT', '0')))
elif name in ('security', 'spctl') or (name == 'xcrun' and args[0] in ('notarytool', 'stapler')):
    sys.exit('Unexpected certificate or notarization dependency')
'''
MOCK_BUILD = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib
root = pathlib.Path.cwd()
app = pathlib.Path(os.environ['APP_OUTPUT'])
(app / 'Contents/MacOS').mkdir(parents=True)
with (root / 'Resources/Info.plist').open('rb') as source:
    info = plistlib.load(source)
info['CFBundleShortVersionString'] = os.environ['APP_VERSION']
info['CFBundleVersion'] = os.environ['APP_BUILD']
with (app / 'Contents/Info.plist').open('wb') as output:
    plistlib.dump(info, output)
(app / 'Contents/MacOS/Shoreline').write_bytes(b'mock universal executable')
(root / 'build-call.json').write_text(json.dumps(dict(version=os.environ['APP_VERSION'], build=os.environ['APP_BUILD'], output=str(app))))
'''


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='shoreline release ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in ('scripts', 'Resources', 'tools', 'docs'):
            (self.root / directory).mkdir()
        for relative in ('scripts/release.sh', 'Resources/Info.plist', 'docs/INSTALL.md',
                         'LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md'):
            shutil.copy(REPOSITORY / relative, self.root / relative)
        self.write_executable(self.root / 'scripts/build.sh', MOCK_BUILD)
        for name in ('xcrun', 'codesign', 'hdiutil', 'security', 'spctl'):
            self.write_executable(self.root / 'tools' / name, MOCK_TOOL)
        self.trace = self.root / 'trace.jsonl'
        self.environment = dict(os.environ, PATH=str(self.root / 'tools') + os.pathsep + os.environ['PATH'],
                                DIST_DIR=str(self.root / 'dist'), TEST_TRACE=str(self.trace), OVERWRITE='0')

    @staticmethod
    def write_executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_release(self, *arguments, **environment):
        return subprocess.run(['/bin/bash', str(self.root / 'scripts/release.sh'), *arguments],
                              cwd=self.root, env=dict(self.environment, **environment),
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_preflight_only_checks_local_build_tools(self):
        result = self.run_release('--check')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.root / 'build-call.json').exists())
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertEqual(calls, [['xcrun', '--find', tool] for tool in ('swiftc', 'actool', 'lipo')])

    def test_release_contains_installation_licenses_and_correct_checksum(self):
        original = (self.root / 'Resources/Info.plist').read_bytes()
        result = self.run_release('1.2.3', '99')
        self.assertEqual(result.returncode, 0, result.stdout)
        image = self.root / 'dist/Shoreline-1.2.3-universal.dmg'
        self.assertEqual(json.loads(image.read_text()),
                         ['Applications', 'INSTALL.md', 'LICENSE', 'NOTICE', 'Shoreline.app', 'THIRD_PARTY_NOTICES.md'])
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        self.assertEqual(image.with_suffix('.dmg.sha256').read_text(), f'{digest}  {image.name}\n')
        self.assertEqual((self.root / 'Resources/Info.plist').read_bytes(), original)
        self.assertEqual(json.loads((self.root / 'build-call.json').read_text())['build'], '99')
        self.assertFalse(list((self.root / 'dist').glob('.release.*')))
        self.assertFalse(list((self.root / 'dist').glob('*.release-lock')))
        self.assertIn('"--timestamp=none", "--sign", "-"', self.trace.read_text())

    def test_verification_failure_preserves_existing_release_and_working_files(self):
        dist = self.root / 'dist'
        dist.mkdir()
        image = dist / 'Shoreline-1.2.3-universal.dmg'
        checksum = image.with_suffix('.dmg.sha256')
        image.write_bytes(b'previous release')
        checksum.write_bytes(b'previous checksum')
        result = self.run_release('1.2.3', '99', OVERWRITE='1', TEST_IMAGE_VERIFY_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(image.read_bytes(), b'previous release')
        self.assertEqual(checksum.read_bytes(), b'previous checksum')
        self.assertTrue(list(dist.glob('.release.*')))
        self.assertFalse(list(dist.glob('*.release-lock')))

    def test_release_rejects_app_with_another_signature(self):
        result = self.run_release('1.2.3', '99', TEST_APP_SIGNATURE='developer-id')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'dist/Shoreline-1.2.3-universal.dmg').exists())

    def test_existing_artifact_and_concurrent_release_fail_before_build(self):
        dist = self.root / 'dist'
        dist.mkdir()
        image = dist / 'Shoreline-1.2.3-universal.dmg'
        image.touch()
        self.assertNotEqual(self.run_release('1.2.3', '99').returncode, 0)
        image.unlink()
        lock = dist / '.Shoreline-1.2.3.release-lock'
        lock.mkdir()
        self.assertNotEqual(self.run_release('1.2.3', '99').returncode, 0)
        self.assertTrue(lock.exists())
        self.assertFalse((self.root / 'build-call.json').exists())

    def test_orphan_checksum_is_protected(self):
        dist = self.root / 'dist'
        dist.mkdir()
        (dist / 'Shoreline-1.2.3-universal.dmg.sha256').touch()
        self.assertNotEqual(self.run_release('1.2.3', '99').returncode, 0)
        self.assertFalse((self.root / 'build-call.json').exists())

    def test_invalid_version_and_build_fail_before_build(self):
        for arguments in [('1.2.3; invalid', '99'), ('1.2.3', 'invalid')]:
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_release(*arguments).returncode, 0)
        self.assertFalse((self.root / 'build-call.json').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
