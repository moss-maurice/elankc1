#!/bin/sh
# Put stock Cypress back as /lib/modules/cyttsp5.ko (no probe).
# Unplug the KC1 digitizer before reboot or the book hangs on the logo.
#
#   ./enable_cyttsp5.sh
#   ./enable_cyttsp5.sh --reboot --touch-unplugged

set -e

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$HERE"

PB_HOST=${PB_HOST:-169.254.0.1}
PB_USER=${PB_USER:-root}
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o LogLevel=ERROR"

REBOOT=0
UNPLUGGED=0
for a in "$@"; do
	case "$a" in
	--reboot) REBOOT=1 ;;
	--touch-unplugged) UNPLUGGED=1 ;;
	esac
done

ok() { echo "[ok]  $1"; }
warn() { echo "[..]  $1"; }
die() { echo "[fail] $1" >&2; exit 1; }

echo ""
echo "PocketBook 740 Pro  —  restore stock Cypress path"
echo ""

if ping -c 1 -W 2 "$PB_HOST" >/dev/null 2>&1; then
	ok "device online  $PB_HOST"
else
	die "no reply from $PB_HOST (USB = Charging)"
fi

echo "[..]  restore Cypress on device  (password once)"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PB_USER@$PB_HOST" "sh -s" <<'REMOTE'
ok() { echo "[ok]  $1"; }
warn() { echo "[..]  $1"; }
fail() { echo "[fail] $1"; }

mount -o rw,remount /dev/root / 2>/dev/null || true

STOCK=""
if [ -f /lib/modules/cyttsp5.driver.ko ]; then
	STOCK=/lib/modules/cyttsp5.driver.ko
elif [ -f /lib/modules/cyttsp5.stock.ko ]; then
	mv /lib/modules/cyttsp5.stock.ko /lib/modules/cyttsp5.driver.ko
	STOCK=/lib/modules/cyttsp5.driver.ko
	ok "migrated .stock -> cyttsp5.driver.ko"
elif [ -f /lib/modules/cyttsp5.ko.bak ]; then
	STOCK=/lib/modules/cyttsp5.ko.bak
fi

if [ -z "$STOCK" ]; then
	fail "no Cypress backup (.driver / .stock / .bak)"
	exit 1
fi

rm -f /lib/modules/cyttsp5.ko
cp "$STOCK" /lib/modules/cyttsp5.ko
chmod 644 /lib/modules/cyttsp5.ko
ok "restored stock Cypress as cyttsp5.ko"

ACCESS=""
if [ -f /lib/modules/cyttsp5_device_access.driver.ko ]; then
	ACCESS=/lib/modules/cyttsp5_device_access.driver.ko
elif [ -f /lib/modules/cyttsp5_device_access.stock.ko ]; then
	mv /lib/modules/cyttsp5_device_access.stock.ko \
		/lib/modules/cyttsp5_device_access.driver.ko
	ACCESS=/lib/modules/cyttsp5_device_access.driver.ko
fi
if [ -n "$ACCESS" ]; then
	cp "$ACCESS" /lib/modules/cyttsp5_device_access.ko
	chmod 644 /lib/modules/cyttsp5_device_access.ko
	ok "restored HID access"
fi

if [ -f /lib/modules/elankc1.driver.ko ]; then
	warn "elankc1.driver.ko left on disk — uninstall_elankc1.sh deletes it"
fi

sync
ok "stock Cypress path restored"
exit 0
REMOTE

if [ "$REBOOT" = "1" ]; then
	if [ "$UNPLUGGED" != "1" ]; then
		die "refusing reboot: pass --touch-unplugged only after the KC1 cable is out"
	fi
	echo "[..]  reboot"
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$PB_USER@$PB_HOST" reboot || true
fi

echo ""
echo "  Power off the device, then unplug the touch cable."
echo ""
