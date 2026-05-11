#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point for the Windows port of ubuntu-setup.
    Equivalent to setup.sh on Linux/macOS.

.DESCRIPTION
    Phase 1 (initial run):
      1. Self-elevates to Administrator.
      2. Validates Windows build (>=17763 / Win 10 1809).
      3. Ensures winget is available.
      4. Installs Git for Windows.
      5. Locates or downloads configure.ps1 and install.ps1 from the repo.
      6. Enables WSL Windows features (DISM - no Store required).
      7. Registers a post-reboot scheduled task to run Phase 2.
      8. Reboots.

    Phase 2 (auto-runs after reboot via scheduled task, -Resume flag):
      1. Runs the WinForms configuration wizard (configure.ps1).
      2. Launches the unattended installer (install.ps1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1

.NOTES
    Supports Windows 10 (1809 / Build 17763) and Windows 11.
    WSL 2 requires Windows 10 2004 (Build 19041) or later.
#>

[CmdletBinding()]
param(
    # Internal flag: set when the script is re-launched after the WSL-feature reboot.
    [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Colour helpers -------------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Blue }
function Write-Info { param([string]$Message) Write-Host "INFO: $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Abort      { param([string]$Message) Write-Host $Message -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }

# -- Self-elevation -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host 'Relaunching with Administrator privileges...' -ForegroundColor Cyan
    $scriptPath = if ((Test-Path variable:PSCommandPath) -and $PSCommandPath) { $PSCommandPath }
                  else {
                      # Running via iex - download to a temp file so -File works
                      $tmp = Join-Path $env:TEMP 'ubuntu-setup-windows.ps1'
                      Invoke-RestMethod 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows/setup.ps1' -OutFile $tmp
                      $tmp
                  }
    $args = @('-ExecutionPolicy','Bypass','-NoProfile','-NoExit','-File',"`"$scriptPath`"")
    if ($Resume) { $args += '-Resume' }
    $proc = Start-Process powershell -ArgumentList $args -Verb RunAs -PassThru -Wait
    exit $proc.ExitCode
}

# -- Top-level error handler - keeps the window open so errors are readable -----
trap {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Read-Host "`nPress Enter to close"
    exit 1
}

# -- Execution policy -----------------------------------------------------------
# Wrap in try/catch: Set-ExecutionPolicy throws a terminating SecurityException
# in PowerShell 5.1 when Group Policy overrides the requested scope, and
# -ErrorAction SilentlyContinue does not suppress terminating errors there.
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop -WarningAction SilentlyContinue
} catch {
    Write-Warn "Could not persist execution policy (likely overridden by Group Policy) - continuing."
}


# -- Script directory -----------------------------------------------------------
$SCRIPT_DIR = if ((Test-Path variable:PSCommandPath) -and $PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $PWD.Path }
Push-Location $SCRIPT_DIR

# -- Windows build validation ---------------------------------------------------
$osBuild = [System.Environment]::OSVersion.Version.Build
Write-Info "Detected Windows build: $osBuild"

if ($osBuild -lt 17763) {
    Abort ("Windows 10 version 1809 (Build 17763) or later is required.`n" +
           "Current build: $osBuild`n" +
           "Please update Windows via Settings > Windows Update and re-run.")
}
if ($osBuild -lt 19041) {
    Write-Warn "Build $osBuild is below 19041 (Windows 10 2004)."
    Write-Warn "WSL 2 requires Build 19041+.  WSL 1 will be configured instead."
    Write-Warn "Run 'winget upgrade --all' or use Windows Update to unlock WSL 2."
}

# -- winget availability --------------------------------------------------------
Write-Step "Checking winget..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn "winget (App Installer) was not found."
    Write-Host ''
    Write-Host "Install 'App Installer' from the Microsoft Store and re-run:" -ForegroundColor Yellow
    Write-Host "  https://aka.ms/getwinget" -ForegroundColor Yellow
    Write-Host ''
    try { Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' } catch { }
    Abort "Please install App Installer and re-run this script."
}

# Bypass certificate pinning - must be done in every elevated session before
# any winget operation to avoid TLS/certificate failures in VMs and corporate
# networks where intermediate CAs intercept Microsoft Store traffic.
Write-Info "Enabling winget certificate pinning bypass..."
winget settings --enable BypassCertificatePinningForMicrosoftStore 2>&1 | Out-Null

Write-Info "Updating winget source lists..."
# Only update the 'winget' source - the 'msstore' source can fail with certificate
# errors in VMs, corporate networks, or fresh Windows installs and is not needed here.
winget source update --name winget 2>&1 | Out-Null

# -- Git for Windows ------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Step "Installing Git for Windows..."
    winget install --id Git.Git `
        --source winget `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --scope machine
    # Refresh PATH for the current session
    foreach ($p in @('C:\Program Files\Git\cmd', 'C:\Program Files\Git\bin')) {
        if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
            $env:PATH = "$p;$env:PATH"
        }
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Abort ("Git installation failed or PATH not refreshed.`n" +
           "Please close this window, open a new PowerShell prompt, and re-run setup.ps1.`n" +
           "Alternatively install Git manually from https://git-scm.com.")
}
Write-Info "Git: $(git --version)"

# -- Locate or download sibling scripts ----------------------------------------
$RAW_BASE = 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows'
$TMP_DIR  = Join-Path $env:TEMP 'ubuntu-setup-windows'
New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null

function Get-SiblingScript {
    param([string]$Name)
    $local = Join-Path $SCRIPT_DIR $Name
    if (Test-Path $local) { return $local }
    Write-Info "Downloading $Name from repository..."
    $dest = Join-Path $TMP_DIR $Name
    try {
        Invoke-WebRequest -Uri "$RAW_BASE/$Name" -OutFile $dest -UseBasicParsing -ErrorAction Stop
    } catch {
        Abort "Failed to download ${Name}: $_"
    }
    return $dest
}

$CONFIGURE_PS1 = Get-SiblingScript 'configure.ps1'
$INSTALL_PS1   = Get-SiblingScript 'install.ps1'

# =============================================================================
# Phase 2 -- runs after reboot (setup.ps1 -Resume, called by scheduled task)
# =============================================================================
if ($Resume) {
    # Remove the scheduled task now that we're running it
    Unregister-ScheduledTask -TaskName 'UbuntuSetupResume' -Confirm:$false -ErrorAction SilentlyContinue

    # -- Configuration wizard --------------------------------------------------
    $CONFIG_FILE = Join-Path $env:USERPROFILE '.setup-windows.json'
    Write-Step "Launching configuration wizard..."

    $confProc = Start-Process powershell -ArgumentList @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-STA',
        '-File', "`"$CONFIGURE_PS1`"",
        '-ConfigFile', "`"$CONFIG_FILE`""
    ) -PassThru -Wait

    if ($confProc.ExitCode -ne 0) {
        Abort "Configuration wizard was cancelled or failed (exit code $($confProc.ExitCode))."
    }
    if (-not (Test-Path $CONFIG_FILE)) {
        Abort "Configuration was not saved.  Re-run setup.ps1 to try again."
    }

    # -- Launch installer (elevated) -------------------------------------------
    Write-Step "Launching installer..."
    $instProc = Start-Process powershell -ArgumentList @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-NoExit',
        '-File', "`"$INSTALL_PS1`"",
        '-ConfigFile', "`"$CONFIG_FILE`""
    ) -Verb RunAs -PassThru -Wait

    if ($instProc.ExitCode -ne 0) {
        Abort "Installer failed (exit code $($instProc.ExitCode)).  Check output above for details."
    }

    Pop-Location
    Write-Step "Setup complete!"
    exit 0
}

# =============================================================================
# Phase 1 -- first run: enable WSL features, register resume task, reboot
# =============================================================================

# -- Enable WSL features -------------------------------------------------------
Write-Step "Enabling WSL Windows features (reboot will follow)..."

$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' -ErrorAction SilentlyContinue
if (-not $wslFeature -or $wslFeature.State -ne 'Enabled') {
    Write-Info "Enabling Microsoft-Windows-Subsystem-Linux..."
    Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' `
        -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Info "Microsoft-Windows-Subsystem-Linux: already enabled."
}

if ($osBuild -ge 19041) {
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' -ErrorAction SilentlyContinue
    if (-not $vmFeature -or $vmFeature.State -ne 'Enabled') {
        Write-Info "Enabling VirtualMachinePlatform (required for WSL 2)..."
        Enable-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' `
            -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
    } else {
        Write-Info "VirtualMachinePlatform: already enabled."
    }
} else {
    Write-Warn "Build $osBuild is below 19041 - VirtualMachinePlatform not available (WSL 1 only)."
}

# -- Stage setup.ps1 to ProgramData so the scheduled task survives the reboot --
$stageDir = 'C:\ProgramData\ubuntu-setup'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$stagedSetup = Join-Path $stageDir 'setup.ps1'

# Guard each copy against the "cannot overwrite item with itself" error that
# occurs when the script is already running from $stageDir.
function Copy-IfDifferent {
    param([string]$Src, [string]$Dst)
    $s = (Resolve-Path $Src -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path)
    $d = (Resolve-Path $Dst -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path)
    if ($s -ine $d) { Copy-Item $Src $Dst -Force }
}

Copy-IfDifferent $CONFIGURE_PS1 (Join-Path $stageDir 'configure.ps1')
Copy-IfDifferent $INSTALL_PS1   (Join-Path $stageDir 'install.ps1')

# If running from a local file, copy that; otherwise use the temp download.
$srcSetup = if ((Test-Path variable:PSCommandPath) -and $PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
Copy-IfDifferent $srcSetup $stagedSetup

# -- Register post-reboot scheduled task ----------------------------------------
Write-Step "Registering resume task (UbuntuSetupResume)..."

$whoami = (Get-CimInstance Win32_ComputerSystem).UserName  # e.g. MACHINE\user
$samUser = if ($whoami -match '\\(.+)$') { $Matches[1] } else { $whoami }

$action  = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -NoExit -File `"$stagedSetup`" -Resume"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $samUser

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId $samUser `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName   'UbuntuSetupResume' `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -Principal  $principal `
    -Force | Out-Null

# Verify it registered
if (-not (Get-ScheduledTask -TaskName 'UbuntuSetupResume' -ErrorAction SilentlyContinue)) {
    Abort "Failed to register scheduled task 'UbuntuSetupResume'."
}
Write-Info "Scheduled task registered.  It will run setup.ps1 -Resume after reboot."

# -- Reboot ---------------------------------------------------------------------
Write-Host ''
Write-Host "Windows features enabled.  The system will reboot in 10 seconds." -ForegroundColor Yellow
Write-Host "After login, the configuration wizard will open automatically."   -ForegroundColor Yellow
Write-Host "Press Ctrl+C to abort the reboot if needed."                       -ForegroundColor Yellow
Write-Host ''

Pop-Location

try {
    shutdown.exe /r /f /t 10
} catch {
    Restart-Computer -Force
}
