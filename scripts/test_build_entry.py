#!/usr/bin/env python3
"""Exercise the real entry/native/packaging scripts with a fake make and compiler.
No network, kernel compilation or writes to the real source tree occur here.
"""
from pathlib import Path
import fcntl
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SOURCE = Path(__file__).resolve().parents[1]
PROFILE = dict(line.split('=', 1) for line in (SOURCE / 'scripts/build_profile.sh').read_text().splitlines() if line.startswith('BUILD_'))
SOC = PROFILE['BUILD_SOC']

class BuildEntryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=SOC + '-entry-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'source'
        self.repo.mkdir()
        files = ['build.sh', 'scripts/build_entry.sh', 'scripts/build_profile.sh', 'scripts/check_lkm.py', PROFILE['BUILD_NATIVE']]
        if SOC == 'sm8550':
            files += ['scripts/build/common.sh', 'scripts/build/build_image.sh', 'scripts/build/pack_anykernel.sh']
        for name in files:
            p = self.repo / name
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / name, p)
        self.put('arch/arm64/configs/' + PROFILE['BUILD_DEFCONFIG'], '# fixture\n')
        self.put('Makefile', 'VERSION = 6\nPATCHLEVEL = 1\nSUBLEVEL = 0\n')
        self.put('scripts/config', '#!/bin/sh\nexit 0\n')
        if SOC == 'sm8550':
            self.put('drivers/misc/fixture', '# retained directory\n')
            for script in ['setup_toolchain.sh', 'apply_features.sh']:
                self.put('scripts/build/' + script, '#!/bin/sh\nexit 0\n')
        else:
            self.put('build/apply_features.sh', '#!/bin/sh\nexit 0\n')
        self.tc = self.base / 'toolchain'
        clang_bin = self.tc / 'clang/host/linux-x86' / PROFILE['BUILD_CLANG'] / 'bin'
        clang_bin.mkdir(parents=True)
        for tool in ['clang', 'ld.lld']:
            p = clang_bin / tool
            p.write_text('#!/bin/sh\necho fixture-compiler\n'); p.chmod(0o755)
        self.ak = self.base / 'anykernel'
        (self.ak / 'tools').mkdir(parents=True)
        (self.ak / 'anykernel.sh').write_text('do.devicecheck=1\ndevice.name1=fixture\n')
        (self.ak / 'tools/ak3-core.sh').write_text('# fixture\n')
        self.bin = self.base / 'bin'; self.bin.mkdir()
        make = self.bin / 'make'
        make.write_text("""#!/usr/bin/env python3
from pathlib import Path
import json, os, sys
args = sys.argv[1:]
out = Path(next(a[2:] for a in args if a.startswith('O=')))
out.mkdir(parents=True, exist_ok=True)
with open(os.environ['MAKE_RECORD'], 'a') as f: f.write(json.dumps(args)+'\\n')
if 'Image' in args:
    if os.environ.get('FAIL_IMAGE') == '1':
        print('error: deliberate make failure'); sys.exit(23)
    image = out/'arch/arm64/boot/Image'; image.parent.mkdir(parents=True,exist_ok=True)
    image.write_bytes(bytes(56)+b'ARM\\x64'+bytes(4))
    rel = out/'include/config/kernel.release'; rel.parent.mkdir(parents=True,exist_ok=True)
    rel.write_text('6.1.0-fixture\\n')
else:
    (out/'.config').write_text('CONFIG_NETFILTER_XT_SET=y\\nCONFIG_REKERNEL=y\\nCONFIG_LSM="capability"\\nCONFIG_MODULES=y\\nCONFIG_KPROBES=y\\nCONFIG_KALLSYMS=y\\nCONFIG_KALLSYMS_ALL=y\\nCONFIG_EXT4_FS=y\\n')
    if os.environ.get('INVALID_CONFIG') == '1':
        with (out/'.config').open('a') as f: f.write('CONFIG_KSU=y\\n')
""")
        make.chmod(0o755)
        self.record = self.base / 'make-record.jsonl'
        self.env = {k: v for k, v in os.environ.items() if k not in [
            'MODE', 'JOBS', 'OUT_DIR', 'TOOLCHAIN_DIR', 'ANYKERNEL_DIR', 'PACK', 'ZIP_AFTER',
            'CI_ARTIFACT_DIR', 'CCACHE_DIR', 'CCACHE_BASEDIR', 'CCACHE_MAXSIZE', 'KERNEL_CACHE_ROOT',
            'FAIL_IMAGE', 'SKIP_TOOLCHAIN_SETUP']}
        self.env.update(PATH=str(self.bin) + ':' + os.environ['PATH'], TOOLCHAIN_DIR=str(self.tc),
                        ANYKERNEL_DIR=str(self.ak), USE_CCACHE='0', MAKE_RECORD=str(self.record))
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)

    def put(self, name, content):
        p = self.repo / name; p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content); p.chmod(0o755)

    def run_build(self, *args, env=None, native=False, repo=None):
        return subprocess.run(['bash', str((repo or self.repo) / (PROFILE['BUILD_NATIVE'] if native else 'build.sh')), *args],
                              cwd=self.base, env=self.env | (env or {}), text=True, capture_output=True, timeout=30)

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def no_build(self):
        self.assertFalse(self.record.exists())
        self.assertFalse((self.repo / '.git/kernel-source-mode').exists())
        self.assertFalse((self.repo / 'out').exists())
        self.assertFalse((self.repo / '.yucca_token').exists())

    def test_check_does_not_modify_sources_or_require_anykernel(self):
        before = {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob('*') if p.is_file()}
        self.ok(self.run_build('--check', env={'ANYKERNEL_DIR': str(self.base / 'missing')}))
        after = {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob('*') if p.is_file()}
        self.assertEqual(before, after); self.no_build()

    def test_pack_requires_anykernel_before_building(self):
        result = self.run_build('--pack', env={'ANYKERNEL_DIR': str(self.base / 'missing')})
        self.assertNotEqual(result.returncode, 0); self.assertIn('AnyKernel3', result.stderr); self.no_build()

    def test_invalid_arguments_stop_before_building(self):
        for args in [('--jobs', '0'), ('--jobs', '-1'), ('--jobs',), ('--mode', 'bad'),
                     ('--typo',), ('lkm', 'resukisu'), ('--out-dir', str(self.repo))]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_build(*args).returncode, 0)
                self.no_build()

    def test_cli_overrides_environment_and_paths_are_relative_to_repo(self):
        result = self.run_build('--mode', 'lkm', '--jobs', '3', '--no-pack', '--out-dir', 'out/custom dir',
                                env={'MODE': 'resukisu', 'JOBS': '7', 'PACK': '1', 'ZIP_AFTER': '0', 'OUT_DIR': 'out/ignored'})
        self.ok(result)
        out = self.repo / 'out/custom dir'
        self.assertTrue((out / 'arch/arm64/boot/Image').exists())
        self.assertFalse(list(self.base.glob('*.zip')))
        records = [json.loads(line) for line in self.record.read_text().splitlines()]
        self.assertTrue(all('-j3' in args and 'O=' + str(out) in args for args in records))

    def test_default_packaging_is_off(self):
        self.ok(self.run_build())
        self.assertTrue((self.repo / 'out' / PROFILE['BUILD_DEFAULT_MODE'] / 'arch/arm64/boot/Image').exists())
        self.assertFalse(list(self.base.rglob('*.zip')))

    def test_lkm_pack_without_mutating_template(self):
        # Each subtest gets its own source worktree; mode isolation is intentional.
        mode = 'lkm'
        before = {str(p.relative_to(self.ak)): p.read_bytes() for p in self.ak.rglob('*') if p.is_file()}
        self.ok(self.run_build(mode, '--pack'))
        out = self.repo / 'out' / mode
        zips = list(out.glob(SOC.upper() + '_LKM_*.zip')); self.assertEqual(len(zips), 1)
        with zipfile.ZipFile(zips[0]) as archive:
            image = 'Image' if SOC == 'sm8550' else 'zImage'
            self.assertEqual(archive.read(image), (out / 'arch/arm64/boot/Image').read_bytes())
            if SOC == 'sm8750': self.assertIn(b'device.name4=psq', archive.read('anykernel.sh'))
        after = {str(p.relative_to(self.ak)): p.read_bytes() for p in self.ak.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        self.assertFalse(list(self.base.glob('*.zip')))

    def test_legacy_native_ci_invocation_publishes_lkm_zip(self):
        self.ok(self.run_build('lkm', native=True, env={'PACK': '1', 'MODE': 'lkm'}))
        zips = list((self.repo / 'out/lkm').glob(SOC.upper() + '_LKM_*.zip'))
        self.assertEqual(len(zips), 1)
        self.assertEqual(zips[0].read_bytes(), (self.base / zips[0].name).read_bytes())

    def test_conflicting_pack_aliases_require_explicit_option(self):
        result = self.run_build('--check', env={'PACK': '1', 'ZIP_AFTER': '0'})
        self.assertNotEqual(result.returncode, 0); self.assertIn('disagree', result.stderr); self.no_build()
        self.ok(self.run_build('--check', '--pack', env={'PACK': '0', 'ZIP_AFTER': '1'}))

    def test_zip_after_legacy_alias(self):
        self.ok(self.run_build('lkm', env={'ZIP_AFTER': '1'}))
        self.assertEqual(len(list((self.repo / 'out/lkm').glob('*.zip'))), 1)

    def test_failed_make_never_packs(self):
        result = self.run_build('lkm', '--pack', env={'FAIL_IMAGE': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.base.rglob('*.zip')))
        self.assertEqual((self.repo / '.git/kernel-source-mode').read_text(), 'lkm\n')

    def test_switching_mode_rejects_prepared_sources(self):
        self.ok(self.run_build('lkm'))
        before = self.record.read_bytes()
        result = self.run_build('resukisu')
        self.assertNotEqual(result.returncode, 0); self.assertIn('Only lkm', result.stderr)
        self.assertEqual(before, self.record.read_bytes())

    def test_source_lock_prevents_concurrent_builds(self):
        with (self.repo / '.git/kernel-build.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_build('lkm')
            self.assertNotEqual(result.returncode, 0); self.assertIn('Another build', result.stderr)
            self.no_build()

    def test_output_lock_prevents_concurrent_builds(self):
        out = self.base / 'external-output'; out.mkdir()
        with (out / '.kernel-build.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_build('lkm', '--out-dir', str(out))
            self.assertNotEqual(result.returncode, 0); self.assertIn('output directory', result.stderr)
            self.no_build()

    def test_git_worktree_file_and_independent_outputs(self):
        subprocess.run(['git', '-C', str(self.repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@invalid',
                        'commit', '-qm', 'Fixture'], check=True)
        wt = self.base / 'worktree'
        subprocess.run(['git', '-C', str(self.repo), 'worktree', 'add', '-q', '--detach', str(wt)], check=True)
        self.ok(self.run_build('lkm', repo=wt))
        self.assertTrue((wt / '.git').is_file())
        self.assertFalse((self.repo / '.git/kernel-source-mode').exists())
        self.ok(self.run_build('lkm'))

    def test_explicit_missing_toolchain_never_silently_falls_back(self):
        (self.repo / 'prebuilts').mkdir()
        result = self.run_build('--check', '--toolchain-dir', 'nonexistent')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('/nonexistent/', result.stderr); self.no_build()


    def test_retired_mode_rejected_from_cli_environment_and_native_path(self):
        for args, env, native in [(('resukisu',), {}, False), (('--mode', 'resukisu'), {}, True),
                                  ((), {'MODE': 'resukisu'}, False)]:
            with self.subTest(args=args, env=env, native=native):
                result = self.run_build(*args, env=env, native=native)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Only lkm', result.stderr)
                self.no_build()

    def test_retired_feature_flags_rejected(self):
        for flag in ['APPLY_SUSFS', 'APPLY_ZEROMOUNT']:
            result = self.run_build(env={flag: '1'})
            self.assertNotEqual(result.returncode, 0)
            self.no_build()

    def test_legacy_source_hooks_rejected_without_reset(self):
        for content in ['source "drivers/kernelsu/Kconfig"', '#ifdef CONFIG_KSU', 'ksu_handle_execve();']:
            self.put('drivers/Kconfig', content + '\n')
            result = self.run_build('--check')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Legacy built-in root', result.stderr)
            self.assertEqual((self.repo / 'drivers/Kconfig').read_text(), content + '\n')
            self.no_build()

    def test_legacy_prepared_tree_marker_rejected(self):
        self.put('.resukisu-patch-state.json', '{}')
        result = self.run_build('--check')
        self.assertNotEqual(result.returncode, 0)
        self.no_build()

    def test_config_guard_prevents_building_or_packing_root_enabled_config(self):
        result = self.run_build('--pack', env={'INVALID_CONFIG': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CONFIG_KSU=y', result.stderr)
        records = [json.loads(line) for line in self.record.read_text().splitlines()]
        self.assertTrue(all('Image' not in args for args in records))
        self.assertFalse(list(self.base.rglob('*.zip')))

if __name__ == '__main__':
    unittest.main()
