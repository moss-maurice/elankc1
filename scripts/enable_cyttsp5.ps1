#Requires -Version 5.1
# Restore stock Cypress cyttsp5.ko on PocketBook 740 Pro over USB SSH (Windows).
# Unplug the KC1 digitizer before reboot or the book hangs on the logo.
#
#   powershell -ExecutionPolicy Bypass -File .\enable_cyttsp5.ps1
#   powershell -ExecutionPolicy Bypass -File .\enable_cyttsp5.ps1 -Reboot -TouchUnplugged

param(
    [string]$HostAddress = "169.254.0.1",
    [string]$User = "root",
    [switch]$Reboot,
    [switch]$TouchUnplugged
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
    Write-Step wait "restore Cypress on device  (password again)"
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
Write-Host "PocketBook 740 Pro  -  restore stock Cypress path"
Write-Host ""

if (Test-Connection -ComputerName $HostAddress -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Write-Step ok "device online"
} else {
    throw "no reply from $HostAddress. USB = Charging."
}

$onDevice = @'
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
	warn "elankc1.driver.ko left on disk - uninstall_elankc1.ps1 deletes it"
fi

sync
ok "stock Cypress path restored"
exit 0
'@

Invoke-RemoteSh -SshArgs $ssh -Remote $remote -Script $onDevice

if ($Reboot) {
    if (-not $TouchUnplugged) {
        throw "refusing reboot: pass -TouchUnplugged only after the KC1 cable is unplugged."
    }
    Write-Step wait "reboot"
    & ssh @ssh $remote "reboot"
}

Write-Host ""
Write-Host "  Power off the device, then unplug the touch cable."
Write-Host ""
