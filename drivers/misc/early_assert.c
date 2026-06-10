// SPDX-License-Identifier: GPL-2.0
/*
 * Early-boot assertion module.
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/string.h>
#include <linux/kthread.h>
#include <linux/wait.h>
#include <linux/delay.h>
#include <linux/slab.h>
#include <linux/printk.h>
#include <linux/atomic.h>
#include <linux/jiffies.h>
#include <linux/err.h>
#include <linux/sched.h>
#include <crypto/sha2.h>

#include "yucca_gate_token.h"

#ifndef YUCCA_EXPECTED_HASH_BYTES
#error "yucca_gate_token.h missing YUCCA_EXPECTED_HASH_BYTES; regenerate via scripts/build/build.sh"
#endif

#define KASSERT_TIMEOUT_SEC  60
#define KASSERT_MAX_INPUT    256
#define KASSERT_ID_SUFFIX    ".By_Yucca"
#define KASSERT_PROC_NAME    "early_assert_status"

static const u8 expected_hash[SHA256_DIGEST_SIZE] = YUCCA_EXPECTED_HASH_BYTES;

/* gate_state: 0 = pending, 1 = pass, 2 = fail */
static atomic_t gate_state = ATOMIC_INIT(0);
static DECLARE_WAIT_QUEUE_HEAD(gate_wq);
static bool bypass_mode_detected;

extern char boot_command_line[];

static ssize_t kassert_write(struct file *f, const char __user *ubuf,
			     size_t len, loff_t *ppos)
{
	char *kbuf;
	char *sep, *id_part, *token_part;
	u8 actual[SHA256_DIGEST_SIZE];
	size_t real_len = len;

	if (atomic_read(&gate_state) != 0)
		return -EBUSY;
	if (len < 8 || len >= KASSERT_MAX_INPUT)
		return -EINVAL;

	kbuf = kmalloc(len + 1, GFP_KERNEL);
	if (!kbuf)
		return -ENOMEM;
	if (copy_from_user(kbuf, ubuf, len)) {
		kfree(kbuf);
		return -EFAULT;
	}
	kbuf[len] = '\0';

	/* trim trailing whitespace */
	while (real_len > 0 &&
	       (kbuf[real_len - 1] == '\n' || kbuf[real_len - 1] == '\r' ||
		kbuf[real_len - 1] == ' '  || kbuf[real_len - 1] == '\t')) {
		kbuf[--real_len] = '\0';
	}

	sep = strchr(kbuf, '|');
	if (!sep) {
		atomic_set(&gate_state, 2);
		wake_up(&gate_wq);
		kfree(kbuf);
		return -EINVAL;
	}
	*sep = '\0';
	id_part = kbuf;
	token_part = sep + 1;

	/* Gate A: id portion must contain the configured suffix. */
	if (!strstr(id_part, KASSERT_ID_SUFFIX)) {
		atomic_set(&gate_state, 2);
		wake_up(&gate_wq);
		kfree(kbuf);
		return -EACCES;
	}

	/* Gate B: sha256(token) must match the embedded constant. */
	sha256(token_part, strlen(token_part), actual);
	if (memcmp(actual, expected_hash, SHA256_DIGEST_SIZE) != 0) {
		atomic_set(&gate_state, 2);
		wake_up(&gate_wq);
		kfree(kbuf);
		return -EACCES;
	}

	atomic_set(&gate_state, 1);
	wake_up(&gate_wq);
	kfree(kbuf);
	return (ssize_t)len;
}

static const struct proc_ops kassert_ops = {
	.proc_write = kassert_write,
};

static int kassert_thread(void *unused)
{
	int state;

	if (bypass_mode_detected) {
#ifndef CONFIG_YUCCA_ROM_GATE_ENFORCE
		pr_info("early_assert: bypassed (recovery/charger/fastbootd)\n");
#endif
		return 0;
	}

#ifndef CONFIG_YUCCA_ROM_GATE_ENFORCE
	pr_info("early_assert: armed; waiting up to %ds for userspace\n",
		KASSERT_TIMEOUT_SEC);
#endif

	wait_event_interruptible_timeout(gate_wq,
					 atomic_read(&gate_state) != 0,
					 KASSERT_TIMEOUT_SEC * HZ);

	state = atomic_read(&gate_state);

	if (state == 1) {
#ifndef CONFIG_YUCCA_ROM_GATE_ENFORCE
		pr_info("early_assert: passed\n");
#endif
		return 0;
	}

#ifdef CONFIG_YUCCA_ROM_GATE_ENFORCE
	/*
	 * Production: emit a kernel BUG. CONFIG_BUG=y in defconfig so this
	 * triggers panic() unconditionally. Output looks like a generic
	 * kernel assertion, not a recognisable lock.
	 */
	BUG();
#else
	if (state == 2)
		pr_warn("early_assert: would-have-BUG'd (token/id mismatch, diagnostic mode)\n");
	else
		pr_warn("early_assert: would-have-BUG'd (timeout, diagnostic mode)\n");
#endif
	return 0;
}

static int __init kassert_init(void)
{
	struct proc_dir_entry *pde;
	struct task_struct *t;

	/*
	 * Parse boot cmdline now (boot_command_line is __initdata and is
	 * freed after init phase; the kthread may run later).
	 */
	if (strstr(boot_command_line, "androidboot.mode=recovery") ||
	    strstr(boot_command_line, "androidboot.mode=charger") ||
	    strstr(boot_command_line, "androidboot.mode=fastbootd"))
		bypass_mode_detected = true;

	pde = proc_create(KASSERT_PROC_NAME, 0222, NULL, &kassert_ops);
	if (!pde) {
		pr_err("early_assert: proc_create failed\n");
#ifdef CONFIG_YUCCA_ROM_GATE_ENFORCE
		BUG();
#else
		return -ENOMEM;
#endif
	}

	t = kthread_run(kassert_thread, NULL, "kassert");
	if (IS_ERR(t)) {
		pr_err("early_assert: kthread_run failed: %ld\n", PTR_ERR(t));
#ifdef CONFIG_YUCCA_ROM_GATE_ENFORCE
		BUG();
#else
		return PTR_ERR(t);
#endif
	}

	return 0;
}
late_initcall(kassert_init);
