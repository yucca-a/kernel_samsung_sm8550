#!/usr/bin/env python3
"""Reject leftover built-in root integration and verify LKM prerequisites."""
from pathlib import Path
import re
import sys

def check_source(root):
    markers = ['.resukisu-patch-state.json', 'drivers/kernelsu', 'fs/susfs.c',
               'fs/zeromount.c', 'include/linux/susfs.h', 'include/linux/susfs_def.h',
               'include/linux/zeromount.h']
    for name in markers:
        p = root / name
        if p.exists() or p.is_symlink():
            raise SystemExit(f'Legacy built-in root source found: {p}. Use a clean worktree; sources are not reset automatically.')
    for name in ['drivers/Kconfig', 'drivers/Makefile', 'fs/Kconfig', 'fs/Makefile',
                 'kernel/sys.c', 'fs/exec.c', 'fs/open.c', 'fs/read_write.c',
                 'fs/namespace.c', 'fs/namei.c', 'fs/readdir.c', 'fs/stat.c',
                 'fs/proc/task_mmu.c', 'include/linux/fs.h', 'include/linux/sched.h']:
        p = root / name
        if p.is_file() and re.search(r'drivers/kernelsu|CONFIG_KSU\b|CONFIG_KSU_|\bksu_handle_|\bsusfs_|\bzeromount_', p.read_text()):
            raise SystemExit(f'Legacy built-in root hooks found in {p}; use a clean worktree.')

def check_config(path):
    config = dict(line.split('=', 1) for line in path.read_text().splitlines() if line.startswith('CONFIG_') and '=' in line)
    for key in ['MODULES', 'KPROBES', 'KALLSYMS', 'KALLSYMS_ALL', 'EXT4_FS']:
        if config.get('CONFIG_' + key) != 'y':
            raise SystemExit(f'LKM prerequisite missing: CONFIG_{key}=y')
    for key, value in config.items():
        if value in ('y', 'm') and (key == 'CONFIG_KSU' or key.startswith('CONFIG_KSU_') or key in [
                'CONFIG_ZEROMOUNT', 'CONFIG_KPM', 'CONFIG_MODULE_SIG_FORCE',
                'CONFIG_MODULE_SIG_PROTECT', 'CONFIG_TRIM_UNUSED_KSYMS']):
            raise SystemExit(f'LKM-only configuration rejects {key}={value}')

if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('source', 'config'):
        raise SystemExit('Usage: check_lkm.py source ROOT | config CONFIG_FILE')
    (check_source if sys.argv[1] == 'source' else check_config)(Path(sys.argv[2]))
