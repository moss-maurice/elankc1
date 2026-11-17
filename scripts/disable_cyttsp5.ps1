#Requires -Version 5.1
# Hide Cypress cyttsp5.ko on PocketBook 740 Pro over USB SSH (Windows).
# After this, the KC1 digitizer can stay plugged in: boot will not hang
# on the logo. No Elan driver is installed. No firmware flash.
#
#   powershell -ExecutionPolicy Bypass -File .\disable_cyttsp5.ps1
#   powershell -ExecutionPolicy Bypass -File .\disable_cyttsp5.ps1 -Reboot

param(
    [string]$HostAddress = "169.254.0.1",
    [string]$User = "root",
    [switch]$Reboot
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
    Write-Step wait "hide Cypress on device  (password again)"
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
Write-Host "PocketBook 740 Pro  -  hide stock Cypress"
Write-Host ""

if (Test-Connection -ComputerName $HostAddress -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Write-Step ok "device online"
} else {
    throw "no reply from $HostAddress. USB = Charging. If hung on logo, unplug the touch cable."
}

$onDevice = @'
ok() { echo "[ok]  $1"; }
fail() { echo "[fail] $1"; }

mount -o rw,remount /dev/root / 2>/dev/null || true

is_stub() {
	strings "$1" 2>/dev/null | grep -Eq 'tpselect|tp_select'
}

if [ -f /lib/modules/cyttsp5.ko ]; then
	if is_stub /lib/modules/cyttsp5.ko; then
		ok "cyttsp5.ko is already the probe - left in place"
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
'@

Invoke-RemoteSh -SshArgs $ssh -Remote $remote -Script $onDevice

if ($Reboot) {
    Write-Step wait "reboot"
    & ssh @ssh $remote "reboot"
}

Write-Host ""
Write-Host "  KC1 cable can stay plugged in."
Write-Host ""
