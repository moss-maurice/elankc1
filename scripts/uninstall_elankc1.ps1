#Requires -Version 5.1
# Remove the Native kernel stack (probe + elankc1) and put stock Cypress
# back as /lib/modules/cyttsp5.ko. Does not remove pbjb / SSH.
# Unplug the KC1 digitizer before reboot or the book hangs on the logo.
#
#   powershell -ExecutionPolicy Bypass -File .\uninstall_elankc1.ps1

param(
    [string]$HostAddress = "169.254.0.1",
    [string]$User = "root"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Status, [string]$Text)
    $tag = switch ($Status) {
        "ok"   { "[ok]" }
        "fail" { "[fail]" }
        default { "[..]" }
    }
    $color = switch ($Status) {
        "ok"   { "Green" }
        "fail" { "Red" }
        default { "DarkGray" }
    }
    Write-Host "$tag  " -ForegroundColor $color -NoNewline
    Write-Host $Text
}

function Invoke-RemoteSh {
    param(
        [string[]]$SshArgs,
        [string]$Remote,
        [string]$Script
    )
    $unix = $Script -replace "`r`n", "`n" -replace "`r", "`n"
    $tmp = Join-Path $env:TEMP "pb-remote.sh"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $unix, $utf8)
    Write-Step wait "copy script  (password once)"
    & scp -q @SshArgs $tmp "${Remote}:/mnt/secure/.pb-run.sh"
    if ($LASTEXITCODE -ne 0) { throw "scp failed ($LASTEXITCODE)" }
    Write-Step wait "uninstall on device  (password again)"
    & ssh @SshArgs $Remote "sh /mnt/secure/.pb-run.sh; e=`$?; rm -f /mnt/secure/.pb-run.sh; exit `$e"
    if ($LASTEXITCODE -ne 0) { throw "remote script failed ($LASTEXITCODE)" }
}

$ssh = @(
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa",
    "-o", "LogLevel=ERROR"
)
$remote = "${User}@${HostAddress}"

Write-Host ""
Write-Host "PocketBook 740 Pro  -  uninstall Elan KC1"
Write-Host ""

if (Test-Connection -ComputerName $HostAddress -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Write-Step ok "device online"
} else {
    throw "no reply from $HostAddress. USB = Charging. If hung on logo, unplug the touch cable."
}

$onDevice = @'
ok() { echo "[ok]  $1"; }
warn() { echo "[..]  $1"; }
fail() { echo "[fail] $1"; }

export PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

is_stub() {
	[ -f "$1" ] && strings "$1" 2>/dev/null | grep -Eq 'tpselect|tp_select'
}

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

mount -o rw,remount /dev/root / 2>/dev/null || true

STOCK=""
if [ -f /lib/modules/cyttsp5.driver.ko ]; then
	STOCK=/lib/modules/cyttsp5.driver.ko
elif [ -f /lib/modules/cyttsp5.stock.ko ]; then
	mv /lib/modules/cyttsp5.stock.ko /lib/modules/cyttsp5.driver.ko
	ok "migrated .stock -> cyttsp5.driver.ko"
	STOCK=/lib/modules/cyttsp5.driver.ko
elif [ -f /lib/modules/cyttsp5.ko.bak ]; then
	cp /lib/modules/cyttsp5.ko.bak /lib/modules/cyttsp5.driver.ko
	ok "migrated .bak -> cyttsp5.driver.ko"
	STOCK=/lib/modules/cyttsp5.driver.ko
fi

if [ -z "$STOCK" ]; then
	if [ -f /lib/modules/cyttsp5.ko ] && ! is_stub /lib/modules/cyttsp5.ko; then
		ok "stock Cypress already at cyttsp5.ko"
	else
		fail "no Cypress backup (.driver / .stock / .bak) - cannot restore"
		exit 1
	fi
else
	cp "$STOCK" /lib/modules/cyttsp5.ko
	chmod 644 /lib/modules/cyttsp5.ko
	ok "restored stock Cypress as cyttsp5.ko"
fi

if is_stub /lib/modules/cyttsp5.ko; then
	fail "cyttsp5.ko is still the probe"
	exit 1
fi

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

rm -f /lib/modules/elankc1.driver.ko /lib/modules/elankc1.ko
rm -f /mnt/secure/elankc1.driver.ko /mnt/secure/elankc1.ko /mnt/secure/tpselect.ko /mnt/secure/tp_select.ko
rm -f /mnt/ext1/elankc1.driver.ko /mnt/ext1/elankc1.ko /mnt/ext1/tpselect.ko /mnt/ext1/tp_select.ko
ok "removed Elan / probe copies"

if [ -f /mnt/secure/etc/init.d/00-z-elan.sh ]; then
	warn "userspace hook still present (elan-d) - use reinstall/rollback to wipe it"
fi

if [ -f /mnt/secure/runonce/jailbreak_startup.sh ]; then
	ok "jailbreak kept"
else
	warn "no jailbreak file on /mnt/secure"
fi

sync
ok "uninstall complete"
exit 0
'@

Invoke-RemoteSh -SshArgs $ssh -Remote $remote -Script $onDevice

Write-Host ""
Write-Host "  Power off the device, then unplug the touch cable."
Write-Host ""
