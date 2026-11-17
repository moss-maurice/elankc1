#!/bin/sh
# Hide Cypress cyttsp5.ko on PocketBook 740 Pro over USB SSH (Linux).
# After this, the KC1 digitizer can stay plugged in: boot will not hang
# on the logo. No Elan driver is installed. No firmware flash.
#
#   ./disable_cyttsp5.sh
#   ./disable_cyttsp5.sh --reboot

set -e

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$HERE"

PB_HOST=${PB_HOST:-169.254.0.1}
PB_USER=${PB_USER:-root}
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o LogLevel=ERROR"

ok() { echo "[ok]  $1"; }
die() { echo "[fail] $1" >&2; exit 1; }

echo ""
echo "PocketBook 740 Pro  —  hide stock Cypress"
echo ""

if ping -c 1 -W 2 "$PB_HOST" >/dev/null 2>&1; then
	ok "device online  $PB_HOST"
else
	die "no reply from $PB_HOST (USB = Charging. If hung on the logo, unplug the touch cable first.)"
fi

echo "[..]  hide Cypress on device  (password once)"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$PB_USER@$PB_HOST" "sh -s" <<'REMOTE'
ok() { echo "[ok]  $1"; }
fail() { echo "[fail] $1"; }

mount -o rw,remount /dev/root / 2>/dev/null || true

is_stub() {
	strings "$1" 2>/dev/null | grep -Eq 'tpselect|tp_select'
}

if [ -f /lib/modules/cyttsp5.ko ]; then
	if is_stub /lib/modules/cyttsp5.ko; then
		ok "cyttsp5.ko is already the probe — left in place"
	else
		if [ ! -f /lib/modules/cyttsp5.driver.ko ]; then
			mv /lib/modules/cyttsp5.ko /lib/modules/cyttsp5.driver.ko
			ok "hid stock Cypress as cyttsp5.driver.ko"
		else
			rm -f /lib/modules/cyttsp5.ko
			ok "removed stock cyttsp5.ko (driver already saved)"
		fi
	fi
else
	ok "cyttsp5.ko already absent"
fi

if [ -f /lib/modules/cyttsp5.ko ] && ! is_stub /lib/modules/cyttsp5.ko; then
	fail "stock Cypress still at cyttsp5.ko"
	exit 1
fi

sync
ok "KC1 cable is safe to leave plugged in"
exit 0
REMOTE

if [ "${1-}" = "--reboot" ]; then
	echo "[..]  reboot"
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$PB_USER@$PB_HOST" reboot || true
fi

echo ""
echo "  KC1 cable can stay plugged in."
echo ""
