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
