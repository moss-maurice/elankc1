# Out-of-tree module for PocketBook 740 Pro (kernel 3.10.65, ARCH=arm).
# KERNELDIR: prepared tree (740-2_defconfig + modules_prepare).
# Packaged copies live in ../build/ via the root Makefile.

KERNELDIR ?= /tmp/kernel-b288
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabi-

obj-m += elankc1.o
obj-m += tpselect.o
ccflags-y += -Wno-error

all:
	$(MAKE) -C $(KERNELDIR) M=$(CURDIR) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules
	$(CROSS_COMPILE)strip --strip-debug elankc1.ko tpselect.ko \
		2>/dev/null || true
	file elankc1.ko tpselect.ko
	ls -l elankc1.ko tpselect.ko

clean:
	$(MAKE) -C $(KERNELDIR) M=$(CURDIR) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) clean

.PHONY: all clean
