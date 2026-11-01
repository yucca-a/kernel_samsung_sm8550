#!/usr/bin/env python3
"""Fault-inject make/tee and exercise the real Image build stage."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).with_name('build_image.sh')
FAKE_MAKE = r"""#!/usr/bin/env python3
import os
from pathlib import Path
import sys
out = Path(os.environ['TEST_OUT'])
counter = out / 'attempts'
n = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(n))
case = os.environ['CASE']
image = out / 'arch/arm64/boot/Image'
if case != 'missing':
    header = bytearray(64)
    header[56:60] = b'ARM\x64'
    image.write_bytes(b'' if case == 'empty' else b'bad' if case == 'invalid' else header)
if case == 'failure' or case == 'mixed':
    print('clang: error: actual compile failure')
if case in ('rename', 'mixed', 'exhaust') and (n == 1 or case != 'rename'):
    print('clang: error: unable to rename temporary file')
    sys.exit(2)
sys.exit(2 if case == 'failure' else 0)
"""

class ImageBuildTests(unittest.TestCase):
    def run_case(self, case, broken_tee=False):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / 'bin').mkdir()
            (p / 'arch/arm64/boot').mkdir(parents=True)
            make = p / 'bin/make'
            make.write_text(FAKE_MAKE)
            make.chmod(0o755)
            if broken_tee:
                tee = p / 'bin/tee'
                tee.write_text('#!/bin/sh\ncat >/dev/null\nexit 1\n')
                tee.chmod(0o755)
            shell = 'source "$1"; log(){ echo "$*"; }; warn(){ echo "$*"; }; die(){ echo "$*" >&2; exit 1; }; build_kernel_image "$TEST_OUT" ARCH=arm64'
            result = subprocess.run(['bash', '-c', shell, 'test', str(HELPER)],
                env={**os.environ, 'CASE':case, 'TEST_OUT':tmp, 'PATH':f'{p}/bin:'+os.environ['PATH']},
                capture_output=True, text=True)
            attempts = int((p / 'attempts').read_text())
            return result, attempts

    def test_success(self):
        result, attempts = self.run_case('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(attempts, 1)

    def test_failed_make_with_valid_image(self):
        result, attempts = self.run_case('failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Build succeeded', result.stdout)
        self.assertEqual(attempts, 1)

    def test_invalid_outputs(self):
        for case in ('empty', 'invalid', 'missing'):
            with self.subTest(case=case):
                result, _ = self.run_case(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Build succeeded', result.stdout)

    def test_known_race_retries(self):
        result, attempts = self.run_case('rename')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(attempts, 2)

    def test_mixed_errors_do_not_retry(self):
        result, attempts = self.run_case('mixed')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(attempts, 1)

    def test_retry_limit(self):
        result, attempts = self.run_case('exhaust')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(attempts, 5)

    def test_log_failure(self):
        result, _ = self.run_case('success', broken_tee=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Build succeeded', result.stdout)

if __name__ == '__main__':
    unittest.main()
