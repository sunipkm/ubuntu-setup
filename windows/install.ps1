#Requires -Version 5.1
<#
.SYNOPSIS
    Main Windows installer for the ubuntu-setup port.
    Equivalent to install.sh on Linux/macOS (Windows-side operations only).

.DESCRIPTION
    Reads the JSON config produced by configure.ps1 and performs:
      1. Hostname rename (if changed)
      2. Git global configuration
      3. Visual Studio Code installation + extension installation
      4. Nerd Fonts + Microsoft Aptos font installation
      5. WSL enablement
      6. Registers wsl_resume.ps1 as a post-reboot scheduled task
      7. Reboots to complete WSL setup

.PARAMETER ConfigFile
    Path to the JSON config file (default: $env:USERPROFILE\.setup-windows.json).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigFile C:\my-config.json
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $env:USERPROFILE '.setup-windows.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Require admin --------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    $proc = Start-Process powershell -ArgumentList @(
        '-ExecutionPolicy', 'Bypass', '-NoProfile',
        '-File', "`"$PSCommandPath`"",
        '-ConfigFile', "`"$ConfigFile`""
    ) -Verb RunAs -PassThru -Wait
    exit $proc.ExitCode
}

# -- Colour helpers -------------------------------------------------------------
function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Blue }
function Write-Info { param([string]$m) Write-Host "INFO: $m" -ForegroundColor Cyan }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Abort      { param([string]$m) Write-Host $m -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }

# -- Global error trap - keeps the elevated window open so errors are readable --
trap {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Read-Host "`nPress Enter to close"
    exit 1
}

# -- Load config ----------------------------------------------------------------
if (-not (Test-Path $ConfigFile)) {
    Abort "Config file not found: $ConfigFile`nRun configure.ps1 first."
}
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Write-Step "Loaded config from $ConfigFile"

$SCRIPT_DIR  = if ($cfg.ScriptDir -and (Test-Path $cfg.ScriptDir)) { $cfg.ScriptDir } else { Split-Path -Parent $PSCommandPath }
$osBuild     = [System.Environment]::OSVersion.Version.Build
$WORK_DIR    = Join-Path $env:TEMP "ubuntu-setup-work-$(Get-Random)"
New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

function Cleanup { Remove-Item $WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue }
try {

# -- Winget certificate bypass -------------------------------------------------
# Must be applied in every elevated session before any winget operation to
# prevent TLS certificate failures in VMs and corporate environments.
Write-Info "Enabling winget certificate pinning bypass..."
winget settings --enable BypassCertificatePinningForMicrosoftStore 2>&1 | Out-Null

# -- Hostname -------------------------------------------------------------------
$desiredHost = $cfg.Hostname.Trim()
if ($desiredHost -and $desiredHost -ne $env:COMPUTERNAME) {
    Write-Step "Renaming computer to '$desiredHost'..."
    Rename-Computer -NewName $desiredHost -Force -ErrorAction SilentlyContinue
    Write-Info "Hostname will change after reboot."
}

# -- Git configuration ----------------------------------------------------------
Write-Step "Configuring git..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    if ($cfg.GitName)  { git config --global user.name  $cfg.GitName  }
    if ($cfg.GitEmail) { git config --global user.email $cfg.GitEmail }
    git config --global init.defaultBranch master 2>$null
    if ($cfg.GpgFingerprint) {
        git config --global user.signingkey  $cfg.GpgFingerprint
        git config --global commit.gpgsign   true
        Write-Info "Git commit signing enabled with key $($cfg.GpgFingerprint)"
    }
} else {
    Write-Warn "git not found on PATH - skipping git config."
}

# -- VS Code --------------------------------------------------------------------
if ($cfg.IsInteractive) {
    Write-Step "Installing Visual Studio Code..."

    $codeInstalled = $false
    $codePath = $null

    # Check if already installed
    foreach ($p in @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )) { if (Test-Path $p) { $codePath = $p; $codeInstalled = $true; break } }

    if (-not $codeInstalled) {
        winget install --id Microsoft.VisualStudioCode `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --override '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
        # Locate code.cmd after install
        foreach ($p in @(
            "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
            "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
        )) { if (Test-Path $p) { $codePath = $p; $codeInstalled = $true; break } }
    }

    if ($codeInstalled -and $codePath) {
        $codeDir = Split-Path -Parent $codePath
        if ($env:PATH -notlike "*$codeDir*") { $env:PATH = "$codeDir;$env:PATH" }
        Write-Info "VS Code: $codePath"

        Write-Step "Installing VS Code extensions..."
        $EXTENSIONS_URL = 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/extensions.txt'
        $extFile = Join-Path $WORK_DIR 'extensions.txt'
        try {
            Invoke-WebRequest -Uri $EXTENSIONS_URL -OutFile $extFile -UseBasicParsing
        } catch {
            # Fall back to local copy if available
            $localExt = Join-Path (Split-Path -Parent $SCRIPT_DIR) 'extensions.txt'
            if (Test-Path $localExt) { Copy-Item $localExt $extFile }
            else { Write-Warn "Could not fetch extensions.txt: $_" }
        }

        if (Test-Path $extFile) {
            $exts = Get-Content $extFile | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }
            $total = $exts.Count
            $i = 0
            $failed = [System.Collections.Generic.List[string]]::new()
            foreach ($ext in $exts) {
                $i++
                Write-Progress -Activity "Installing VS Code extensions" -Status $ext -PercentComplete (($i / $total) * 100)
                try {
                    $out = & cmd /c "`"$codePath`" --install-extension $ext --force" 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warn "Extension failed to install (skipping): $ext"
                        $failed.Add($ext)
                    }
                } catch {
                    Write-Warn "Extension failed to install (skipping): $ext - $_"
                    $failed.Add($ext)
                }
            }
            Write-Progress -Activity "Installing VS Code extensions" -Completed
            $succeeded = $total - $failed.Count
            Write-Info "Extensions: $succeeded/$total installed successfully."
            if ($failed.Count -gt 0) {
                Write-Warn "Failed extensions ($($failed.Count)): $($failed -join ', ')"
            }
        }
    } else {
        Write-Warn "VS Code install failed or code.cmd not found.  Skipping extensions."
    }
}

# -- Fonts ----------------------------------------------------------------------
if ($cfg.IsInteractive) {
    Write-Step "Installing fonts..."

    # P/Invoke for broadcasting WM_FONTCHANGE after font installation
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FontInstaller {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResourceW(string lpFileName);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_FONTCHANGE = 0x001D;
    public static void BroadcastFontChange() {
        SendMessage((IntPtr)0xFFFF, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero);
    }
}
'@ -Language CSharp -ErrorAction SilentlyContinue

    $FONT_DIR = "$env:SystemRoot\Fonts"
    $FONT_REG = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    Add-Type -AssemblyName System.Drawing

    function Install-FontFile {
        param([string]$Path)
        $fileName = Split-Path -Leaf $Path
        $dest = Join-Path $FONT_DIR $fileName
        if (Test-Path $dest) { return }  # already installed
        Copy-Item -Path $Path -Destination $dest -Force
        # Get font display name
        try {
            $pfc = New-Object System.Drawing.Text.PrivateFontCollection
            $pfc.AddFontFile($dest)
            $fontName = $pfc.Families[0].Name
            $pfc.Dispose()
            Set-ItemProperty -Path $FONT_REG -Name "$fontName (TrueType)" -Value $fileName -Type String
        } catch {
            # Fall back to using the filename as the key
            $key = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            Set-ItemProperty -Path $FONT_REG -Name "$key (TrueType)" -Value $fileName -Type String
        }
    }

    # Fetch latest nerd-fonts release
    try {
        $nfRelease = (Invoke-RestMethod -Uri 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest' -UseBasicParsing).tag_name
        Write-Info "Nerd Fonts release: $nfRelease"
    } catch {
        Write-Warn "Could not query GitHub API for nerd-fonts version; skipping font download."
        $nfRelease = $null
    }

    if ($nfRelease) {
        $nfBase = "https://github.com/ryanoasis/nerd-fonts/releases/download/$nfRelease"

        foreach ($font in @('CascadiaCode', 'Meslo')) {
            $zipPath = Join-Path $WORK_DIR "$font.zip"
            $extractDir = Join-Path $WORK_DIR $font
            Write-Info "Downloading $font Nerd Font..."
            try {
                Invoke-WebRequest -Uri "$nfBase/$font.zip" -OutFile $zipPath -UseBasicParsing
                Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
                Get-ChildItem -Path $extractDir -Filter '*.ttf' -Recurse | ForEach-Object {
                    Install-FontFile -Path $_.FullName
                }
            } catch {
                Write-Warn "Failed to download/install $font font: $_"
            }
        }
    }

    # Microsoft Aptos fonts
    Write-Info "Downloading Microsoft Aptos fonts..."
    $aptosZip = Join-Path $WORK_DIR 'aptos.zip'
    try {
        Invoke-WebRequest -Uri 'https://download.microsoft.com/download/8/6/0/860a94fa-7feb-44ef-ac79-c072d9113d69/Microsoft%20Aptos%20Fonts.zip' `
            -OutFile $aptosZip -UseBasicParsing
        $aptosDir = Join-Path $WORK_DIR 'aptos'
        Expand-Archive -Path $aptosZip -DestinationPath $aptosDir -Force
        Get-ChildItem -Path $aptosDir -Filter '*.ttf' -Recurse | ForEach-Object {
            Install-FontFile -Path $_.FullName
        }
    } catch {
        Write-Warn "Failed to download/install Aptos fonts: $_"
    }

    # Broadcast font change to all applications
    try { [FontInstaller]::BroadcastFontChange() } catch { }
    Write-Info "Font installation complete."
}

# -- WSL ------------------------------------------------------------------------
Write-Step "Enabling Windows Subsystem for Linux features..."

# Always check and enable both features individually via DISM/Enable-WindowsOptionalFeature.
# This is reliable across all Windows editions and network environments, unlike
# 'wsl --install' which depends on the Microsoft Store / Windows Update.
# Enable-WindowsOptionalFeature is idempotent - it is safe to run when already enabled.

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

# Check if WSL kernel is already functional. If so, skip the reboot path later.
$wslFunctional = $false
try {
    $null = & "$env:SystemRoot\System32\wsl.exe" --status 2>&1
    $wslFunctional = ($LASTEXITCODE -eq 0)
} catch { }
Write-Info "WSL kernel functional: $wslFunctional"

# -- Save phase into config -----------------------------------------------------
$cfgObj = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Add-Member -InputObject $cfgObj -MemberType NoteProperty -Name 'Phase' -Value 'wsl-enabled' -Force
$cfgObj | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

# -- Locate wsl_resume.ps1 -----------------------------------------------------
# IMPORTANT: never store these in $env:TEMP - that path differs between the
# elevated install session and the scheduled task session after reboot, and
# temp folders may be purged.  Use $env:ProgramData\ubuntu-setup instead.
$RAW_BASE    = 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows'
$PERSIST_DIR = Join-Path $env:ProgramData 'ubuntu-setup'
New-Item -ItemType Directory -Path $PERSIST_DIR -Force | Out-Null

# wsl_resume.ps1
$WSL_RESUME_SRC = Join-Path $SCRIPT_DIR 'wsl_resume.ps1'
$WSL_RESUME     = Join-Path $PERSIST_DIR 'wsl_resume.ps1'
if (Test-Path $WSL_RESUME_SRC) {
    # Resolve paths before copying to avoid "cannot overwrite item with itself"
    # when install.ps1 is already running from PERSIST_DIR.
    $srcResolved = (Resolve-Path $WSL_RESUME_SRC -ErrorAction SilentlyContinue)?.Path
    $dstResolved = (Resolve-Path $WSL_RESUME      -ErrorAction SilentlyContinue)?.Path
    if ($srcResolved -ine $dstResolved) { Copy-Item $WSL_RESUME_SRC $WSL_RESUME -Force }
} else {
    Write-Info "Downloading wsl_resume.ps1..."
    try {
        Invoke-WebRequest -Uri "$RAW_BASE/wsl_resume.ps1" -OutFile $WSL_RESUME -UseBasicParsing
    } catch {
        Abort "Failed to download wsl_resume.ps1: $_"
    }
}

# wsl_bootstrap.sh
$WSL_BOOTSTRAP_SRC = Join-Path $SCRIPT_DIR 'wsl_bootstrap.sh'
$WSL_BOOTSTRAP     = Join-Path $PERSIST_DIR 'wsl_bootstrap.sh'
if (Test-Path $WSL_BOOTSTRAP_SRC) {
    $srcB = (Resolve-Path $WSL_BOOTSTRAP_SRC -ErrorAction SilentlyContinue)?.Path
    $dstB = (Resolve-Path $WSL_BOOTSTRAP      -ErrorAction SilentlyContinue)?.Path
    if ($srcB -ine $dstB) { Copy-Item $WSL_BOOTSTRAP_SRC $WSL_BOOTSTRAP -Force }
} else {
    Write-Info "Downloading wsl_bootstrap.sh..."
    try {
        Invoke-WebRequest -Uri "$RAW_BASE/wsl_bootstrap.sh" -OutFile $WSL_BOOTSTRAP -UseBasicParsing
    } catch {
        Write-Warn "Failed to download wsl_bootstrap.sh: $_"
    }
}

# GPG secret key - stage it now so it survives across reboots and session changes.
# The original file may be on removable media that won't be present after reboot.
$GPG_KEY_STAGED = ''
if ($cfg.GpgKeyFile -and (Test-Path $cfg.GpgKeyFile)) {
    $GPG_KEY_STAGED = Join-Path $PERSIST_DIR 'gpg-secret-key.asc'
    Copy-Item $cfg.GpgKeyFile $GPG_KEY_STAGED -Force
    Write-Info "GPG key staged to: $GPG_KEY_STAGED"
} elseif ($cfg.GpgKeyFile) {
    Write-Warn "GpgKeyFile '$($cfg.GpgKeyFile)' not found; GPG key will not be imported into WSL."
}

Write-Info "Scripts staged to: $PERSIST_DIR"

# Store paths into config so wsl_resume.ps1 can find them
# (done before the functional check so the paths are recorded either way)
$cfgObj2 = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Add-Member -InputObject $cfgObj2 -MemberType NoteProperty -Name 'WslResumeScript'    -Value $WSL_RESUME       -Force
Add-Member -InputObject $cfgObj2 -MemberType NoteProperty -Name 'WslBootstrapScript' -Value $WSL_BOOTSTRAP    -Force
Add-Member -InputObject $cfgObj2 -MemberType NoteProperty -Name 'GpgKeyStaged'       -Value $GPG_KEY_STAGED   -Force
$cfgObj2 | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

# -- If WSL was already functional, run wsl_resume directly (no reboot needed) --
if ($wslFunctional) {
    Write-Step "WSL already present - running post-install steps now (no reboot required)..."
    $resumeProc = Start-Process powershell -ArgumentList @(
        '-ExecutionPolicy', 'Bypass', '-NoProfile', '-NoExit',
        '-File', "`"$WSL_RESUME`"",
        '-ConfigFile', "`"$ConfigFile`""
    ) -PassThru -Wait
    if ($resumeProc.ExitCode -ne 0) {
        Abort "WSL post-install failed (exit code $($resumeProc.ExitCode))."
    }
    exit 0   # triggers finally { Cleanup }; skips task registration and reboot
}

# -- Register post-reboot scheduled task ----------------------------------------
Write-Step "Registering post-reboot scheduled task (ubuntu-setup-wsl-resume)..."

$taskName = 'ubuntu-setup-wsl-resume'
# Remove any stale registration
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ("-ExecutionPolicy Bypass -NoProfile -NoExit -WindowStyle Normal " +
               "-File `"$WSL_RESUME`" -ConfigFile `"$ConfigFile`"")

# Trigger: at logon of the current (non-elevated) user.
# We identify the real logged-on user because this script runs elevated.
# Get-CimInstance is preferred over the deprecated Get-WmiObject.
$loggedOnUser = $null
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($cs.UserName) { $loggedOnUser = $cs.UserName }
} catch { }

# Normalise to bare username for local accounts.
# Task Scheduler accepts domain\user for domain accounts but expects just
# the SAM name (or COMPUTERNAME\user) for local accounts. Using the bare
# SAM name works for both when combined with LogonType Interactive.
if ($loggedOnUser) {
    # Strip any domain/machine prefix from local accounts
    if ($loggedOnUser -match '^([^\\]+)\\(.+)$') {
        $domainPart = $Matches[1]
        $userPart   = $Matches[2]
        if ($domainPart -eq $env:COMPUTERNAME) {
            $loggedOnUser = $userPart   # local account: use bare username
        }
        # else: domain account - keep full DOMAIN\user
    }
} else {
    $loggedOnUser = $env:USERNAME
}
Write-Info "Scheduling task for user: $loggedOnUser"

$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $loggedOnUser
# LogonType Interactive: task fires when the user logs on interactively.
# This is required for AtLogOn tasks on local user accounts without stored
# credentials. RunLevel Highest requests elevation; for admin accounts this
# works without a UAC prompt. wsl_resume.ps1 also self-elevates as fallback.
$principal = New-ScheduledTaskPrincipal -UserId $loggedOnUser `
    -LogonType Interactive -RunLevel Highest
# Note: omit -DisallowDemandStart; it is a [switch] and passing $false without
# a colon (-DisallowDemandStart:$false) corrupts parameter binding in PS 5.1.
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -RestartCount 0

Register-ScheduledTask `
    -TaskName  $taskName `
    -Action    $action `
    -Trigger   $trigger `
    -Principal $principal `
    -Settings  $settings `
    -Force | Out-Null

# Verify the task was actually registered and its status is sane
$regTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $regTask) {
    Abort "Scheduled task '$taskName' could not be verified after registration."
}
Write-Info "Scheduled task '$taskName' registered (State: $($regTask.State), User: $loggedOnUser)."

# -- Countdown and reboot -------------------------------------------------------
Write-Host ''
Write-Host '=======================================================' -ForegroundColor Cyan
Write-Host '  WSL has been enabled.  A reboot is required.' -ForegroundColor Yellow
Write-Host '  After reboot, the setup will continue automatically.' -ForegroundColor Yellow
Write-Host '=======================================================' -ForegroundColor Cyan
Write-Host ''

for ($s = 10; $s -ge 1; $s--) {
    Write-Host "`r  Rebooting in $s second(s)...  Press Ctrl+C to cancel." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ''

} finally {
    Cleanup
}

# Use shutdown.exe directly - more reliable than Restart-Computer across all
# Windows editions and execution contexts (Group Policy, hypervisors, etc.).
# /r = reboot, /f = force-close apps, /t 0 = no delay.
Write-Info "Initiating system reboot via shutdown.exe..."
$shutdownResult = & "$env:SystemRoot\System32\shutdown.exe" /r /f /t 5 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "shutdown.exe failed (exit $LASTEXITCODE): $shutdownResult"
    Write-Warn "Falling back to Restart-Computer..."
    try {
        Restart-Computer -Force -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Could not initiate reboot: $_" -ForegroundColor Red
        Write-Host "Please reboot manually to complete WSL setup." -ForegroundColor Yellow
        Read-Host "`nPress Enter to close"
        exit 1
    }
}
