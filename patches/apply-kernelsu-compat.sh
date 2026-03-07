#!/bin/bash
set -e

KSU_DIR="drivers/kernelsu"

echo "Applying KernelSU Linux 5.4 compatibility fixes..."

# 1. Fix allowlist.c - add sched/task.h and use true instead of TWA_RESUME
sed -i '6a #include <linux/sched/task.h>' "$KSU_DIR/allowlist.c"
sed -i 's/TWA_RESUME/true/g' "$KSU_DIR/allowlist.c"

# 2. Fix app_profile.c - seccomp filter_count and seccomp_filter_release
sed -i '92a #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    atomic_set(\&current->seccomp.filter_count, 0);\n#endif' "$KSU_DIR/app_profile.c"
sed -i '239a #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    atomic_set(\&tsk->seccomp.filter_count, 0);\n#endif' "$KSU_DIR/app_profile.c"

# Replace seccomp_filter_release with version check
sed -i 's/seccomp_filter_release(fake);/#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    seccomp_filter_release(fake);\n#else\n    put_seccomp_filter(fake);\n#endif/g' "$KSU_DIR/app_profile.c"

# 3. Fix sucompat.c - pgtable.h location
sed -i '5,6d' "$KSU_DIR/sucompat.c"
sed -i '4a #include <linux/version.h>\n#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)\n#include <linux/pgtable.h>\n#else\n#include <asm/pgtable.h>\n#endif' "$KSU_DIR/sucompat.c"

# 4. Fix util.c - pgtable.h and mmap_read_trylock
sed -i '2d' "$KSU_DIR/util.c"
sed -i '1a #include <linux/version.h>\n#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)\n#include <linux/pgtable.h>\n#else\n#include <asm/pgtable.h>\n#endif\n#include <linux/sched/mm.h>\n\n#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)\n#define mmap_read_trylock(mm) down_read_trylock(\&(mm)->mmap_sem)\n#define mmap_read_unlock(mm) up_read(\&(mm)->mmap_sem)\n#endif' "$KSU_DIR/util.c"

# 5. Fix seccomp_cache.h - add stubs for older kernels
cat > "$KSU_DIR/seccomp_cache.h" << 'EOF'
#ifndef __KSU_H_SECCOMP_CACHE
#define __KSU_H_SECCOMP_CACHE

#include <linux/fs.h>
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 2)
extern void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr);
extern void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr);
#else
static inline void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr) {}
static inline void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr) {}
#endif

#endif
EOF

# 6. Fix file_wrapper.c - security_inode_init_security_anon stub
sed -i '20a \n#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)\nstatic inline int security_inode_init_security_anon(struct inode *inode,\n                                                     const struct qstr *name,\n                                                     const struct inode *context_inode)\n{\n    return 0;\n}\n#endif' "$KSU_DIR/file_wrapper.c"

# 7. Fix kernel_umount.c - path_umount compatibility
sed -i '11a #include <linux/version.h>' "$KSU_DIR/kernel_umount.c"
sed -i 's/extern int path_umount/#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)\nextern int path_umount/g' "$KSU_DIR/kernel_umount.c"
sed -i '/^static void ksu_umount_mnt/i #else\nstatic void ksu_umount_mnt(struct path *path, int flags)\n{\n    pr_info("kernel_umount not supported on kernel < 5.11\\n");\n}\n#endif' "$KSU_DIR/kernel_umount.c"

# 8. Fix su_mount_ns.c - path_mount compatibility
sed -i '23,25d' "$KSU_DIR/su_mount_ns.c"
sed -i '22a \n#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)\nextern int path_mount(const char *dev_name, struct path *path,\n                      const char *type_page, unsigned long flags,\n                      void *data_page);\n#else\nstatic int ksu_path_mount(const char *dev_name, struct path *path,\n                          const char *type_page, unsigned long flags,\n                          void *data_page)\n{\n    pr_info("path_mount not supported on kernel < 5.11\\n");\n    return -ENOSYS;\n}\n#define path_mount ksu_path_mount\n#endif' "$KSU_DIR/su_mount_ns.c"

# 9. Fix pkg_observer.c - fsnotify_ops signature
sed -i '25,42d' "$KSU_DIR/pkg_observer.c"
sed -i '24a \nstatic int ksu_handle_event(struct fsnotify_group *group,\n                            struct inode *inode,\n                            u32 mask, const void *data, int data_type,\n                            const struct qstr *file_name, u32 cookie,\n                            struct fsnotify_iter_info *iter_info)\n{\n    if (!file_name)\n        return 0;\n    if (mask \& FS_ISDIR)\n        return 0;\n    if (file_name->len == 13 \&\& !memcmp(file_name->name, "packages.list", 13)) {\n        pr_info("packages.list detected: %d\\n", mask);\n        track_throne(false);\n    }\n    return 0;\n}\n\nstatic const struct fsnotify_ops ksu_ops = {\n    .handle_event = ksu_handle_event,\n};' "$KSU_DIR/pkg_observer.c"

# 10. Fix selinux/sepolicy.c - filename_trans for Linux 5.4
sed -i '482,545d' "$KSU_DIR/selinux/sepolicy.c"
sed -i '481a \nstatic bool add_filename_trans(struct policydb *db, const char *s,\n                               const char *t, const char *c, const char *d,\n                               const char *o)\n{\n    struct type_datum *src, *tgt, *def;\n    struct class_datum *cls;\n    struct filename_trans *ft;\n    struct filename_trans_datum *datum, *old_datum;\n\n    src = symtab_search(\&db->p_types, s);\n    if (src == NULL) {\n        pr_warn("source type %s does not exist\\n", s);\n        return false;\n    }\n    tgt = symtab_search(\&db->p_types, t);\n    if (tgt == NULL) {\n        pr_warn("target type %s does not exist\\n", t);\n        return false;\n    }\n    cls = symtab_search(\&db->p_classes, c);\n    if (cls == NULL) {\n        pr_warn("class %s does not exist\\n", c);\n        return false;\n    }\n    def = symtab_search(\&db->p_types, d);\n    if (def == NULL) {\n        pr_warn("default type %s does not exist\\n", d);\n        return false;\n    }\n\n    ft = kzalloc(sizeof(*ft), GFP_ATOMIC);\n    if (!ft)\n        return false;\n\n    ft->stype = src->value;\n    ft->ttype = tgt->value;\n    ft->tclass = cls->value;\n    ft->name = kstrdup(o, GFP_ATOMIC);\n    if (!ft->name) {\n        kfree(ft);\n        return false;\n    }\n\n    old_datum = hashtab_search(db->filename_trans, ft);\n    if (old_datum) {\n        old_datum->otype = def->value;\n        kfree(ft->name);\n        kfree(ft);\n        return true;\n    }\n\n    datum = kzalloc(sizeof(*datum), GFP_ATOMIC);\n    if (!datum) {\n        kfree(ft->name);\n        kfree(ft);\n        return false;\n    }\n    datum->otype = def->value;\n\n    if (hashtab_insert(db->filename_trans, ft, datum)) {\n        kfree(datum);\n        kfree(ft->name);\n        kfree(ft);\n        return false;\n    }\n\n    ebitmap_set_bit(\&db->filename_trans_ttypes, tgt->value - 1, 1);\n    return true;\n}' "$KSU_DIR/selinux/sepolicy.c"

# 11. Fix selinux/rules.c - selinux_state access
sed -i '10a #include "../../../security/selinux/include/security.h"' "$KSU_DIR/selinux/rules.c"
sed -i '16,22s/.*/static struct policydb *get_policydb(void)\n{\n    struct policydb *db;\n    struct selinux_ss *ss = selinux_state.ss;\n    db = \&ss->policydb;\n    return db;\n}/' "$KSU_DIR/selinux/rules.c"

# 12. Create kernel compat header
cat > "$KSU_DIR/ksu_kernel_compat.h" << 'EOF'
#ifndef __KSU_KERNEL_COMPAT_H__
#define __KSU_KERNEL_COMPAT_H__

#include <linux/version.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
#define KSU_TASK_WORK_ADD_RESUME true
#else
#define KSU_TASK_WORK_ADD_RESUME TWA_RESUME
#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)
#include <linux/pgtable.h>
#else
#include <asm/pgtable.h>
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
#include <linux/uaccess.h>

static inline long ksu_strncpy_from_user_nofault(char *dst, const char __user *src, long count)
{
    long ret = strncpy_from_user(dst, src, count);
    if (ret < 0)
        return -EFAULT;
    return ret;
}

static inline long ksu_copy_from_user_nofault(void *dst, const void __user *src, size_t size)
{
    if (copy_from_user(dst, src, size))
        return -EFAULT;
    return 0;
}

static inline long ksu_copy_to_user_nofault(void __user *dst, const void *src, size_t size)
{
    if (copy_to_user(dst, src, size))
        return -EFAULT;
    return 0;
}

#define strncpy_from_user_nofault ksu_strncpy_from_user_nofault
#define copy_from_user_nofault ksu_copy_from_user_nofault
#define copy_to_user_nofault ksu_copy_to_user_nofault
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)
#define security_inode_init_security_anon(inode, qname, context_inode) 0
#endif

#endif
EOF

# 13. Add compat header to files that need it
for f in ksud.c sucompat.c syscall_hook_manager.c; do
    if ! grep -q "ksu_kernel_compat.h" "$KSU_DIR/$f"; then
        sed -i '1i #include "ksu_kernel_compat.h"' "$KSU_DIR/$f"
    fi
done

# 14. Fix Makefile for in-tree build
cat > "$KSU_DIR/Makefile" << 'EOF'
obj-$(CONFIG_KSU) += kernelsu.o

kernelsu-objs := ksu.o
kernelsu-objs += allowlist.o
kernelsu-objs += app_profile.o
kernelsu-objs += apk_sign.o
kernelsu-objs += sucompat.o
kernelsu-objs += syscall_hook_manager.o
kernelsu-objs += throne_tracker.o
kernelsu-objs += pkg_observer.o
kernelsu-objs += setuid_hook.o
kernelsu-objs += kernel_umount.o
kernelsu-objs += supercalls.o
kernelsu-objs += su_mount_ns.o
kernelsu-objs += feature.o
kernelsu-objs += ksud.o
kernelsu-objs += seccomp_cache.o
kernelsu-objs += file_wrapper.o
kernelsu-objs += util.o
kernelsu-objs += tiny_sulog.o

ifeq ($(CONFIG_KSU_MANUAL_SU), y)
ccflags-y += -DCONFIG_KSU_MANUAL_SU
kernelsu-objs += manual_su.o
endif

kernelsu-objs += selinux/selinux.o
kernelsu-objs += selinux/sepolicy.o
kernelsu-objs += selinux/rules.o

ccflags-y += -I$(srctree)/security/selinux -I$(srctree)/security/selinux/include
ccflags-y += -I$(objtree)/security/selinux -include $(srctree)/include/uapi/asm-generic/errno.h
ccflags-y += -Wno-strict-prototypes -Wno-int-conversion -Wno-gcc-compat -Wno-missing-prototypes
ccflags-y += -Wno-declaration-after-statement -Wno-unused-function -Wno-unused-variable

KSU_VERSION := 40538
KSU_VERSION_FULL := v4.1.1-6c624249@main
ccflags-y += -DKSU_VERSION=$(KSU_VERSION)
ccflags-y += -DKSU_VERSION_FULL=\"$(KSU_VERSION_FULL)\"

obj-$(CONFIG_KPM) += kpm/
EOF

echo "KernelSU compatibility patches applied successfully!"
echo "Note: Some features (kernel_umount, path_mount) are disabled on kernel < 5.11"