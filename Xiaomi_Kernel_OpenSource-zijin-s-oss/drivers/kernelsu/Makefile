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
