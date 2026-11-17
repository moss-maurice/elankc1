#!/bin/sh
# Put the PocketBook 740 Pro touch stack back to factory:
#   /lib/modules/cyttsp5.ko              = stock Cypress (not the probe)
#   /lib/modules/cyttsp5_device_access.ko = stock, if a copy exists
# Removes probe / Elan / userspace elan-d no matter how the files are named.
# Detects modules by strings (tpselect / elankc1 / cyttsp5), not by filename.
# Does not remove pbjb / SSH. Does not insmod Cypress now.
# Unplug KC1 before reboot or the book hangs on the logo.
#
#   ./restore_factory.sh

set -e

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$HERE"

PB_HOST=${PB_HOST:-169.254.0.1}
PB_USER=${PB_USER:-root}
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o LogLevel=ERROR"

ok() { echo "[ok]  $1"; }
die() { echo "[fail] $1" >&2; exit 1; }

echo ""
echo "PocketBook 740 Pro  —  restore factory touch"
echo ""

if ping -c 1 -W 2 "$PB_HOST" >/dev/null 2>&1; then
	ok "device online  $PB_HOST"
else
	die "no reply from $PB_HOST (USB = Charging. If hung on the logo, unplug the touch cable first.)"
fi

echo "[..]  restore on device  (password once)"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PB_USER@$PB_HOST" "sh -s" <<'REMOTE'
ok() { echo "[ok]  $1"; }
warn() { echo "[..]  $1"; }
fail() { echo "[fail] $1"; }

export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

has_str() {
	[ -f "$1" ] && strings "$1" 2>/dev/null | grep -q "$2"
}

kind_of() {
	f=$1
	if [ ! -f "$f" ]; then
		echo missing
	elif has_str "$f" tpselect || has_str "$f" tp_select; then
		echo probe
	elif has_str "$f" elankc1 || has_str "$f" elan_kc1; then
		echo elan
	elif has_str "$f" device_access; then
		echo access
	elif has_str "$f" cyttsp5; then
		echo cypress
	else
		echo other
	fi
}

STOCK=""
ACCESS=""
for f in \
	/lib/modules/cyttsp5.ko \
	/lib/modules/cyttsp5.driver.ko \
	/lib/modules/cyttsp5.stock.ko \
	/lib/modules/cyttsp5.ko.bak \
	/lib/modules/elan_kc1.ko \
	/lib/modules/elankc1.ko \
	/lib/modules/elankc1.driver.ko \
	/lib/modules/tpselect.ko \
	/lib/modules/tp_select.ko \
	/lib/modules/cyttsp5_device_access.ko \
	/lib/modules/cyttsp5_device_access.driver.ko \
	/lib/modules/cyttsp5_device_access.stock.ko \
	/mnt/secure/elankc1.ko \
	/mnt/secure/elankc1.driver.ko \
	/mnt/secure/tpselect.ko \
	/mnt/secure/tp_select.ko \
	/mnt/secure/elan_kc1.ko \
	/mnt/ext1/elankc1.ko \
	/mnt/ext1/elankc1.driver.ko \
	/mnt/ext1/tpselect.ko \
	/mnt/ext1/tp_select.ko \
	/mnt/ext1/elan_kc1.ko
do
	[ -f "$f" ] || continue
	k=$(kind_of "$f")
	if [ "$k" = "cypress" ] && [ -z "$STOCK" ]; then
		STOCK=$f
	fi
	if [ "$k" = "access" ] && [ -z "$ACCESS" ]; then
		ACCESS=$f
	fi
done

for f in /lib/modules/*elan* /lib/modules/*kc1* /lib/modules/*tpselect* /lib/modules/*tp_select* \
	/lib/modules/cyttsp5*
do
	[ -f "$f" ] || continue
	k=$(kind_of "$f")
	if [ "$k" = "cypress" ] && [ -z "$STOCK" ]; then
		STOCK=$f
	fi
	if [ "$k" = "access" ] && [ -z "$ACCESS" ]; then
		ACCESS=$f
	fi
done

killall elan-d 2>/dev/null || true
killall elan-tiny 2>/dev/null || true
killall elan-touchd 2>/dev/null || true
killall elan-sniff 2>/dev/null || true
sleep 1

rmmod elankc1 2>/dev/null || true
rmmod elan_kc1 2>/dev/null || true
rmmod tpselect 2>/dev/null || true
rmmod tp_select 2>/dev/null || true
rmmod cyttsp5 2>/dev/null || true
rmmod ektf3908 2>/dev/null || true
rmmod ektf3908_pro 2>/dev/null || true

if [ -d /sys/class/gpio/gpio47 ]; then
	echo 47 > /sys/class/gpio/unexport 2>/dev/null || true
fi
if [ -d /sys/class/gpio/gpio48 ]; then
	echo 48 > /sys/class/gpio/unexport 2>/dev/null || true
fi

chattr -i /mnt/secure/runonce/zz-boot-elan.sh 2>/dev/null || true
chattr -i /mnt/secure/etc/init.d/00-z-elan.sh 2>/dev/null || true
chattr -i /mnt/secure/etc /mnt/secure/etc/init.d 2>/dev/null || true

rm -f /mnt/secure/etc/init.d/00-z-elan.sh \
	/mnt/secure/etc/init.d/00-z-elan.sh.off \
	/mnt/secure/etc/init.d/03-elan.sh \
	/mnt/secure/etc/init.d/80-elan.sh
rm -f /mnt/secure/runonce/zz-boot-elan.sh
rm -f /mnt/ext1/system/init.d/00-z-elan.sh \
	/mnt/ext1/system/init.d/03-elan.sh \
	/mnt/ext1/system/init.d/80-elan.sh \
	/mnt/ext1/system/init.d/zz-boot-elan.sh
rm -f /mnt/secure/elan-d /mnt/secure/elan-d.new /mnt/secure/elan-tiny \
	/mnt/secure/elan-touchd /mnt/secure/elan-sniff
rm -f /mnt/secure/tp-io /mnt/secure/tp-pwr /mnt/secure/tp-scan /mnt/secure/twi2mux
rm -f /mnt/secure/start-elan.sh /mnt/secure/boot-elan.sh /mnt/secure/boot-elan-bg.sh \
	/mnt/secure/00-z-elan.sh
rm -f /mnt/secure/elan.cal /mnt/secure/elan.log /mnt/secure/start-elan.log \
	/mnt/secure/boot-elan.log
ok "removed userspace Elan hooks"

mount -o rw,remount /dev/root / 2>/dev/null || true

if [ -z "$STOCK" ]; then
	fail "no stock Cypress .ko (looked by content, not by name)"
	exit 1
fi

ok "using Cypress from $STOCK"
cp "$STOCK" /lib/modules/cyttsp5.ko
chmod 644 /lib/modules/cyttsp5.ko

if [ "$(kind_of /lib/modules/cyttsp5.ko)" != "cypress" ]; then
	fail "cyttsp5.ko after copy is $(kind_of /lib/modules/cyttsp5.ko), not stock Cypress"
	exit 1
fi
ok "restored stock Cypress as cyttsp5.ko"

if [ -n "$ACCESS" ]; then
	cp "$ACCESS" /lib/modules/cyttsp5_device_access.ko
	chmod 644 /lib/modules/cyttsp5_device_access.ko
	ok "restored HID access"
fi

removed=0
for f in \
	/lib/modules/cyttsp5.driver.ko \
	/lib/modules/cyttsp5.stock.ko \
	/lib/modules/cyttsp5.ko.bak \
	/lib/modules/elan_kc1.ko \
	/lib/modules/elankc1.ko \
	/lib/modules/elankc1.driver.ko \
	/lib/modules/tpselect.ko \
	/lib/modules/tp_select.ko \
	/lib/modules/cyttsp5_device_access.driver.ko \
	/lib/modules/cyttsp5_device_access.stock.ko \
	/mnt/secure/elankc1.ko \
	/mnt/secure/elankc1.driver.ko \
	/mnt/secure/tpselect.ko \
	/mnt/secure/tp_select.ko \
	/mnt/secure/elan_kc1.ko \
	/mnt/ext1/elankc1.ko \
	/mnt/ext1/elankc1.driver.ko \
	/mnt/ext1/tpselect.ko \
	/mnt/ext1/tp_select.ko \
	/mnt/ext1/elan_kc1.ko \
	/mnt/ext1/ektf3908.ko \
	/mnt/ext1/ektf3908-pro.ko
do
	[ -f "$f" ] || continue
	k=$(kind_of "$f")
	case "$k" in
	probe|elan|cypress|access)
		rm -f "$f"
		removed=$((removed + 1))
		;;
	esac
done

for f in /lib/modules/*; do
	[ -f "$f" ] || continue
	[ "$f" = "/lib/modules/cyttsp5.ko" ] && continue
	[ "$f" = "/lib/modules/cyttsp5_device_access.ko" ] && continue
	k=$(kind_of "$f")
	case "$k" in
	probe|elan)
		rm -f "$f"
		removed=$((removed + 1))
		;;
	esac
done
ok "removed $removed leftover module file(s)"

if [ -f /mnt/secure/runonce/jailbreak_startup.sh ]; then
	ok "jailbreak kept"
else
	warn "no jailbreak file on /mnt/secure"
fi

sync
ok "factory touch restored"
exit 0
REMOTE

echo ""
echo "  Power off the device, then unplug the touch cable."
echo ""
