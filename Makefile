# Build elankc1.ko + tpselect.ko, then copy modules and scripts into build/.
KERNELDIR ?= /tmp/kernel-b288
BUILDDIR := build

all:
	$(MAKE) -C src KERNELDIR=$(KERNELDIR)
	mkdir -p $(BUILDDIR)
	cp -f src/elankc1.ko src/tpselect.ko $(BUILDDIR)/
	cp -f scripts/*.sh scripts/*.ps1 scripts/README.md $(BUILDDIR)/
	$(MAKE) checksums

clean:
	$(MAKE) -C src KERNELDIR=$(KERNELDIR) clean

checksums:
	@if command -v sha256sum >/dev/null 2>&1; then \
		(cd $(BUILDDIR) && sha256sum elankc1.ko tpselect.ko > SHA256SUMS); \
	else \
		echo "sha256sum not found; skip SHA256SUMS"; \
	fi

distclean:
	rm -rf $(BUILDDIR)

.PHONY: all clean checksums distclean
