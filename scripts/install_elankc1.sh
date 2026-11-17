#!/bin/sh
# Install Elan driver + tpselect probe onto PocketBook 740 Pro over USB SSH.
# Prerequisites: pbjb, USB = charging, ping 169.254.0.1.
# Stops elan-d. Does not flash firmware. Does not reboot.
#
#   ./install_elankc1.sh
#   ./install_elankc1.sh --direct
#   ./install_elankc1.sh --force
#   ./install_elankc1.sh --on-device --native   # already on the book

set -e

ON_DEVICE=0
NATIVE=1
FORCE=0
for a in "$@"; do
	case "$a" in
	--on-device) ON_DEVICE=1 ;;
	--native|native) NATIVE=1 ;;
	--direct|direct) NATIVE=0 ;;
	--force|force) FORCE=1 ;;
	esac
done

ok() { echo "[ok]  $1"; }
warn() { echo "[..]  $1"; }
fail() { echo "[fail] $1"; }
die() { echo "[fail] $1" >&2; exit 1; }

install_on_device() {
	export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

	elf_ok() {
		hexdump -C -n 4 "$1" 2>/dev/null | grep -q '7f 45 4c 46'
	}

	is_stub() {
		[ -f "$1" ] && strings "$1" 2>/dev/null | grep -Eq 'tpselect|tp_select'
	}

	same_ko() {
		[ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2" 2>/dev/null
	}

	mod_loaded() {
		grep -q "^$1 " /proc/modules 2>/dev/null
	}

	run_insmod() {
		if [ -x /sbin/insmod ]; then
			/sbin/insmod "$@"
		elif [ -x /bin/busybox ]; then
			/bin/busybox insmod "$@"
		else
			insmod "$@"
		fi
	}

	summarize_probe() {
		if dmesg | grep -Eq 'tpselect: Elan hello|tp_select: Elan hello'; then
			ok "digitizer: Elan (hello 55 at 0x10)"
		elif dmesg | grep -Eq 'tpselect: Cypress ACK|tp_select: Cypress ACK'; then
			ok "digitizer: Cypress (ACK at 0x24)"
		elif dmesg | grep -Eq 'tpselect: no digitizer|tp_select: no digitizer'; then
			warn "digitizer: none (cable unplugged - expected during install)"
		else
			warn "digitizer: probe loaded, no hello/ACK yet"
		fi
		if grep -q 'Name="cyttsp5"' /proc/bus/input/devices 2>/dev/null; then
			ok "input Name=cyttsp5"
		else
			warn "input not up yet (normal until the next boot)"
		fi
	}

	load_probe() {
		if mod_loaded tpselect || mod_loaded tp_select; then
			ok "probe already loaded"
			summarize_probe
			return 0
		fi
		if [ "$FORCE" = "1" ]; then
			run_insmod -f /lib/modules/cyttsp5.ko
			ir=$?
		else
			run_insmod /lib/modules/cyttsp5.ko
			ir=$?
		fi
		if [ "$ir" -ne 0 ]; then
			fail "insmod probe exit $ir"
			exit 1
		fi
		ok "probe loaded"
		summarize_probe
	}

	KO=/mnt/secure/elankc1.ko
	STUB=/mnt/secure/tpselect.ko
	ELAN=/lib/modules/elankc1.driver.ko
	PROBE=/lib/modules/cyttsp5.ko
	STOCK=/lib/modules/cyttsp5.driver.ko

	if [ ! -f "$KO" ] || [ ! -f "$STUB" ]; then
		fail "missing $KO or $STUB"
		exit 1
	fi
	if ! elf_ok "$KO" || ! elf_ok "$STUB"; then
		fail "not ELF (want 7f 45 4c 46)"
		exit 1
	fi
	if ! is_stub "$STUB"; then
		fail "tpselect.ko has no probe marker"
		exit 1
	fi
	ok "ELF on device"

	if [ -f /mnt/secure/etc/init.d/00-z-elan.sh ]; then
		mv /mnt/secure/etc/init.d/00-z-elan.sh /mnt/secure/etc/init.d/00-z-elan.sh.off
		ok "disabled userspace hook 00-z-elan.sh"
	elif [ -f /mnt/secure/etc/init.d/00-z-elan.sh.off ]; then
		ok "userspace hook already off"
	fi

	elan_pid=$(pidof elan-d 2>/dev/null || true)
	if [ -n "$elan_pid" ]; then
		killall elan-d 2>/dev/null || true
		ok "stopped elan-d"
	fi

	# Re-run with the same modules: leave a live probe alone.
	if [ "$NATIVE" = "1" ] && is_stub "$PROBE" && [ -f "$STOCK" ] && \
		same_ko "$KO" "$ELAN" && same_ko "$STUB" "$PROBE"; then
		ok "Native stack already installed (probe + elankc1 + Cypress backup)"
		load_probe
		sync
		ok "setup complete"
		exit 0
	fi

	need_replace=0
	if [ "$NATIVE" = "1" ]; then
		same_ko "$KO" "$ELAN" || need_replace=1
		same_ko "$STUB" "$PROBE" || need_replace=1
	else
		same_ko "$KO" "$ELAN" || need_replace=1
	fi

	if [ "$need_replace" = "1" ]; then
		mod_loaded elankc1 && rmmod elankc1 2>/dev/null || true
		mod_loaded elan_kc1 && rmmod elan_kc1 2>/dev/null || true
		mod_loaded tpselect && rmmod tpselect 2>/dev/null || true
		mod_loaded tp_select && rmmod tp_select 2>/dev/null || true
	fi

	mount -o rw,remount /dev/root / 2>/dev/null || true

	if is_stub "$PROBE"; then
		ok "cyttsp5.ko already the probe"
	elif [ -f "$PROBE" ]; then
		if [ ! -f "$STOCK" ]; then
			mv "$PROBE" "$STOCK"
			ok "stock Cypress saved as cyttsp5.driver.ko"
		else
			rm -f "$PROBE"
			ok "stock Cypress already saved"
		fi
	elif [ -f "$STOCK" ]; then
		ok "stock Cypress already saved"
	fi

	if [ -f /lib/modules/cyttsp5.stock.ko ] && [ ! -f "$STOCK" ]; then
		mv /lib/modules/cyttsp5.stock.ko "$STOCK"
		ok "migrated .stock -> cyttsp5.driver.ko"
	fi
	if [ -f /lib/modules/cyttsp5.ko.bak ] && [ ! -f "$STOCK" ]; then
		mv /lib/modules/cyttsp5.ko.bak "$STOCK"
		ok "migrated .bak -> cyttsp5.driver.ko"
	fi

	if [ -f /lib/modules/cyttsp5_device_access.stock.ko ] && \
		[ ! -f /lib/modules/cyttsp5_device_access.driver.ko ]; then
		mv /lib/modules/cyttsp5_device_access.stock.ko \
			/lib/modules/cyttsp5_device_access.driver.ko
	fi
	if [ -f /lib/modules/cyttsp5_device_access.ko ]; then
		if [ ! -f /lib/modules/cyttsp5_device_access.driver.ko ]; then
			mv /lib/modules/cyttsp5_device_access.ko \
				/lib/modules/cyttsp5_device_access.driver.ko
		else
			rm -f /lib/modules/cyttsp5_device_access.ko
		fi
		ok "hid cyttsp5_device_access"
	elif [ -f /lib/modules/cyttsp5_device_access.driver.ko ]; then
		ok "HID access already hidden"
	fi

	if same_ko "$KO" "$ELAN"; then
		ok "elankc1.driver.ko already current"
	else
		cp "$KO" "$ELAN"
		chmod 644 "$ELAN"
		ok "installed elankc1.driver.ko"
	fi
	rm -f /lib/modules/elankc1.ko

	if [ "$NATIVE" = "1" ]; then
		if [ ! -f "$STOCK" ]; then
			fail "no Cypress backup - will not replace cyttsp5.ko"
			exit 1
		fi
		if is_stub "$PROBE" && same_ko "$STUB" "$PROBE"; then
			ok "probe already at cyttsp5.ko"
		else
			cp "$STUB" "$PROBE"
			chmod 644 "$PROBE"
			ok "probe installed as cyttsp5.ko"
		fi
		load_probe
	else
		if mod_loaded elankc1 || mod_loaded elan_kc1; then
			ok "elankc1 already loaded"
		elif [ "$FORCE" = "1" ]; then
			run_insmod -f "$ELAN"
			ir=$?
			if [ "$ir" -ne 0 ]; then
				warn "live insmod elankc1 failed (no hello yet) - files are on disk"
			else
				ok "elankc1 loaded"
			fi
		else
			run_insmod "$ELAN"
			ir=$?
			if [ "$ir" -ne 0 ]; then
				warn "live insmod elankc1 failed (no hello yet) - files are on disk"
			else
				ok "elankc1 loaded"
			fi
		fi
		summarize_probe
	fi

	sync
	ok "setup complete"
	exit 0
}

if [ "$ON_DEVICE" = "1" ]; then
	install_on_device
fi

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$HERE"

PB_HOST=${PB_HOST:-169.254.0.1}
PB_USER=${PB_USER:-root}
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o LogLevel=ERROR"

[ -f elankc1.ko ] || die "missing $HERE/elankc1.ko"
[ -f tpselect.ko ] || die "missing $HERE/tpselect.ko"

mode=native
[ "$NATIVE" = "1" ] || mode=direct

echo ""
echo "PocketBook 740 Pro  —  Elan KC1  ($mode)"
echo ""

if ping -c 1 -W 2 "$PB_HOST" >/dev/null 2>&1; then
	ok "device online  $PB_HOST"
else
	die "no reply from $PB_HOST (USB = Charging, not PC storage)"
fi

warn "copy modules  (password once)"
# shellcheck disable=SC2086
scp -q $SSH_OPTS elankc1.ko tpselect.ko "$PB_USER@$PB_HOST:/mnt/secure/"
ok "copied to /mnt/secure/"

flags="--on-device"
if [ "$NATIVE" = "1" ]; then
	flags="$flags --native"
else
	flags="$flags --direct"
fi
[ "$FORCE" = "1" ] && flags="$flags --force"

warn "setup on device  (password again)"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PB_USER@$PB_HOST" "sh -s -- $flags" < "$0"

echo ""
echo "  Power off the device, then plug in the touch cable."
echo ""
