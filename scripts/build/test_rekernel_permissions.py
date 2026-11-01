#!/usr/bin/env python3
"""Run the real Re:Kernel operation tables through this tree's permission guards.

Host-side test with stub capabilities/handlers. It does not replace Android
SELinux, daemon capability or real-device Netlink integration tests.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = next(p for p in Path(__file__).resolve().parents if (p / 'net/netlink/genetlink.c').is_file())
feature = root / 'build/features/rekernel'
if not feature.exists():
    feature = root / 'drivers/rekernel'
source = (feature / 'rekernel_netlink.c').read_text()
core = (root / 'net/netlink/genetlink.c').read_text()
ops = re.search(r'static const struct genl_ops rekernel_genl_ops\[\] = \{.*?\n\};', source, re.S)[0]
groups = re.search(r'static const struct genl_multicast_group rekernel_genl_mcgrps\[\] = \{.*?\n\};', source, re.S)[0]
start = core.index('if ((op.flags & GENL_ADMIN_PERM)')
end = core.index('return -EPERM;', core.index('GENL_UNS_ADMIN_PERM', start)) + len('return -EPERM;')
command_guard = core[start:end]
start = core.index('if ((grp->flags &')
end = core.index('break;', start)
group_guard = core[start:end]
constants = '\n'.join(line for file in ('include/uapi/linux/genetlink.h','include/net/genetlink.h')
    for line in (root / file).read_text().splitlines()
    if re.match(r'#define\s+GENL_(?:ADMIN_PERM|UNS_ADMIN_PERM|MCAST_CAP_NET_ADMIN|MCAST_CAP_SYS_ADMIN)\s',line))
prefix = r"""
#include <assert.h>
#include <stdbool.h>
#include <errno.h>
#include <stdio.h>
#define BIT(n) (1U << (n))
#define CAP_NET_ADMIN 12
#define CAP_SYS_ADMIN 21
#include "rekernel.h"
struct sk_buff { int unused; };
struct genl_info { int unused; };
struct genl_ops { unsigned int cmd, flags; int (*doit)(struct sk_buff *, struct genl_info *); };
struct genl_multicast_group { const char *name; unsigned int flags; bool cap_sys_admin; };
struct test_net { void *user_ns; };
static bool admin;
static int modifications;
static bool netlink_capable(struct sk_buff *s, int cap) { return admin; }
static bool netlink_ns_capable(struct sk_buff *s, void *ns, int cap) { return admin; }
static bool ns_capable(void *ns, int cap) { return admin; }
static int rekernel_genl_add_monitor_net(struct sk_buff *s, struct genl_info *i) { ++modifications; return 0; }
static int rekernel_genl_del_monitor_net(struct sk_buff *s, struct genl_info *i) { ++modifications; return 0; }
static int rekernel_genl_get_version(struct sk_buff *s, struct genl_info *i) { return 0; }
"""
program = prefix + constants + '\n' + ops + '\n' + groups + r"""
static int command(struct genl_ops op) {
    struct sk_buff *skb = NULL;
    struct test_net storage = {}, *net = &storage;
""" + command_guard + '\nreturn op.doit(NULL, NULL);\n}\n' + r"""
static int subscribe(const struct genl_multicast_group *grp) {
    struct test_net storage = {}, *net = &storage;
    int ret = 0;
""" + group_guard + '\nreturn ret;\n}\n' + r"""
int main(void) {
    for (int allowed = 0; allowed <= 1; ++allowed) {
        admin = allowed;
        for (unsigned int i = 0; i < sizeof(rekernel_genl_ops)/sizeof(rekernel_genl_ops[0]); ++i) {
            struct genl_ops op = rekernel_genl_ops[i];
            int before = modifications;
            int rc = command(op);
            if (op.cmd == REKERNEL_C_GET_VERSION) {
                assert(rc == 0 && modifications == before);
            } else if (allowed) {
                assert(rc == 0 && modifications == before + 1);
            } else {
                assert(rc == -EPERM && modifications == before);
            }
        }
        for (unsigned int i = 0; i < sizeof(rekernel_genl_mcgrps)/sizeof(rekernel_genl_mcgrps[0]); ++i)
            assert(subscribe(&rekernel_genl_mcgrps[i]) == (allowed ? 0 : -EPERM));
    }
    puts("ReKernel permissions: monitor commands/events require CAP_NET_ADMIN; version stays public");
}
"""
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p/'test.c').write_text(program)
    subprocess.run([os.environ.get('HOSTCC','cc'),'-std=gnu11','-Wall','-Werror','-I',str(feature),str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
