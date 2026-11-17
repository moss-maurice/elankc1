#Requires -Version 5.1
# Copy Elan modules to PocketBook 740 Pro and install.
# Default: Native - probe at /lib/modules/cyttsp5.ko. Does not reboot.
#   Power off, then plug in the touch cable.
# -Direct: old live insmod (ENODEV if the panel is unpowered).
param(
    [string]$HostAddr = "169.254.0.1",
    [string]$User = "root",
    [int]$PingSeconds = 90,
    [switch]$Native,
    [switch]$Direct,
    [switch]$Force
)
if ($Native -and $Direct) {
    throw "use either -Native or -Direct, not both"
}

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stageRoot = "C:\pb-touch"
$stageDir = Join-Path $stageRoot "elankc1"
$ko = Join-Path $here "elankc1.ko"
$probe = Join-Path $here "tpselect.ko"
$remoteSh = Join-Path $here "install_elankc1.sh"
$sshCmd = Get-Command ssh -ErrorAction SilentlyContinue
$scpCmd = Get-Command scp -ErrorAction SilentlyContinue
$plink = Get-Command plink -ErrorAction SilentlyContinue
$pscp = Get-Command pscp -ErrorAction SilentlyContinue
$useOpenSsh = [bool]($sshCmd -and $scpCmd)

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

if (-not (Test-Path $ko)) { throw "missing $ko - use a release zip or run make (output in build/)" }
if (-not (Test-Path $probe)) { throw "missing $probe - rebuild on Linux (make, output in build/)" }
if (-not (Test-Path $remoteSh)) { throw "missing $remoteSh" }

$mode = if ($Direct) { "direct" } else { "native" }
Write-Host ""
Write-Host "PocketBook 740 Pro  -  Elan KC1  ($mode)"
Write-Host ""

New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Copy-Item -Force $ko (Join-Path $stageDir "elankc1.ko")
Copy-Item -Force $probe (Join-Path $stageDir "tpselect.ko")
$unix = [System.IO.File]::ReadAllText($remoteSh) -replace "`r`n", "`n" -replace "`r", "`n"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $stageDir "install_elankc1.sh"), $unix, $utf8)
$ko = Join-Path $stageDir "elankc1.ko"
$probe = Join-Path $stageDir "tpselect.ko"
$remoteSh = Join-Path $stageDir "install_elankc1.sh"
Write-Step ok "staged to $stageDir"

function Test-ElfMz($path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 4) { throw "$path too small" }
    if ($b[0] -eq 0x4D -and $b[1] -eq 0x5A) {
        throw "$path is a Windows PE (MZ). Rebuild on Linux (make, output in build/)."
    }
    if ($b[0] -ne 0x7F -or $b[1] -ne 0x45 -or $b[2] -ne 0x4C -or $b[3] -ne 0x46) {
        throw "$path is not an ELF kernel module"
    }
}

Test-ElfMz $ko
Test-ElfMz $probe
Write-Step ok ("modules ready  elankc1.ko={0}  tpselect.ko={1}" -f (Get-Item $ko).Length, (Get-Item $probe).Length)

# Prefer Windows OpenSSH. PuTTY pscp with a pinned hostkey fails after
# jailbreak reinstall (new sshd key -> "Host key not in manually configured list").
$plinkArgs = @(
    "-ssh", "-P", "22",
    "${User}@${HostAddr}"
)
$pscpArgs = @(
    "-q", "-P", "22"
)
$openSshOpts = @(
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa",
    "-o", "LogLevel=ERROR",
    "-o", "StrictHostKeyChecking=accept-new"
)

function Wait-Reader {
    Write-Step wait "USB charging / NDIS  -  waiting for $HostAddr"
    $deadline = (Get-Date).AddSeconds($PingSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Connection -ComputerName $HostAddr -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Write-Step ok "device online"
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "no ping $HostAddr - USB Charging, jailbreak, adapter 169.254.0.x"
}

Wait-Reader

Write-Step wait "copy modules  (password once)"
if ($useOpenSsh) {
    & $scpCmd.Source -q @openSshOpts $ko $probe $remoteSh "${User}@${HostAddr}:/mnt/secure/"
    if ($LASTEXITCODE -ne 0) { throw "scp failed ($LASTEXITCODE)" }
} elseif ($pscp) {
    & $pscp.Source @pscpArgs $ko $probe $remoteSh "${User}@${HostAddr}:/mnt/secure/"
    if ($LASTEXITCODE -ne 0) { throw "pscp failed ($LASTEXITCODE)" }
} else {
    throw "need OpenSSH scp or PuTTY pscp in PATH"
}
Write-Step ok "copied to /mnt/secure/"

$flags = @("--on-device")
if ($Direct) { $flags += "--direct" } else { $flags += "--native" }
if ($Force) { $flags += "--force" }
$remoteCmd = "sh /mnt/secure/install_elankc1.sh " + ($flags -join " ")

Write-Step wait "setup on device  (password again)"
if ($useOpenSsh) {
    & $sshCmd.Source @openSshOpts "${User}@${HostAddr}" $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw "ssh failed ($LASTEXITCODE)" }
} elseif ($plink) {
    & $plink.Source @plinkArgs $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw "plink failed ($LASTEXITCODE)" }
} else {
    throw "need OpenSSH ssh or PuTTY plink in PATH"
}

Write-Host ""
Write-Host "  Power off the device, then plug in the touch cable."
Write-Host ""
