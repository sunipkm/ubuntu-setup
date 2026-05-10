#Requires -Version 5.1
<#
.SYNOPSIS
    Post-reboot continuation of the Windows ubuntu-setup installer.
    Registered as a one-shot scheduled task by install.ps1.

.DESCRIPTION
    Runs automatically after the reboot triggered by install.ps1 (which enabled
    WSL).  Performs:
      1. Unregisters itself so it never runs again.
      2. Installs the WSL kernel update on Windows 10 (if needed).
      3. Sets WSL default version to 2.
      4. Installs the chosen WSL distro.
      5. Creates the Linux user and configures passwordless sudo for the install.
      6. Writes ~/.setup.conf (Bash format) inside WSL.
      7. Copies wsl_bootstrap.sh into WSL and runs it.
      8. Cleans up passwordless sudo and shows completion summary.

.PARAMETER ConfigFile
    Path to the JSON config file written by configure.ps1 / install.ps1.

.NOTES
    This script is not meant to be run directly.  It is launched by the
    "ubuntu-setup-wsl-resume" scheduled task created by install.ps1.
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $env:USERPROFILE '.setup-windows.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Colour helpers -------------------------------------------------------------
function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Blue }
function Write-Info { param([string]$m) Write-Host "INFO: $m" -ForegroundColor Cyan }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Abort      { param([string]$m) Write-Host $m -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }

# -- Global error trap - keeps the window open so errors are readable ----------
trap {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Read-Host "`nPress Enter to close"
    exit 1
}

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

# -- 1. Unregister this task immediately (run-once guarantee) -------------------
Write-Step "Unregistering scheduled task..."
Unregister-ScheduledTask -TaskName 'ubuntu-setup-wsl-resume' -Confirm:$false -ErrorAction SilentlyContinue

# -- Load config ----------------------------------------------------------------
if (-not (Test-Path $ConfigFile)) {
    Abort "Config file not found: $ConfigFile"
}
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json

$WslDistro    = $cfg.WslDistro
$WslUsername  = $cfg.WslUsername
$WslBootstrap = $cfg.WslBootstrapScript
$osBuild      = [System.Environment]::OSVersion.Version.Build

# -- Update phase ---------------------------------------------------------------
Add-Member -InputObject $cfg -MemberType NoteProperty -Name 'Phase' -Value 'wsl-resume' -Force
$cfg | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

# -- 2. WSL kernel update (Windows 10 only, < Build 22000) ---------------------
if ($osBuild -lt 22000) {
    Write-Step "Updating WSL 2 kernel (Windows 10)..."
    try {
        wsl --update 2>&1 | Out-Null
        Write-Info "WSL kernel updated via 'wsl --update'."
    } catch {
        # Fallback: download the standalone MSI kernel updater
        Write-Warn "wsl --update failed; attempting standalone kernel MSI..."
        $msiPath = Join-Path $env:TEMP 'wsl_update_x64.msi'
        try {
            Invoke-WebRequest `
                -Uri 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' `
                -OutFile $msiPath -UseBasicParsing
            Start-Process msiexec -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
            Write-Info "WSL kernel MSI installed."
        } catch {
            Write-Warn "WSL kernel update failed: $_.  WSL 2 may not be available."
        }
    }
}

# -- 3. Set WSL default version -------------------------------------------------
Write-Step "Setting WSL default version to 2..."
try {
    wsl --set-default-version 2 2>&1 | Out-Null
    Write-Info "WSL 2 set as default."
} catch {
    Write-Warn "Could not set WSL default version to 2: $_"
}

# -- 4. Install WSL distro ------------------------------------------------------
Write-Step "Installing WSL distro: $WslDistro..."

# Check if already installed
$installed = (wsl --list --quiet 2>&1) -join "`n"
if ($installed -notmatch [regex]::Escape($WslDistro)) {
    wsl --install -d $WslDistro --no-launch 2>&1 | Out-Null
    Write-Info "Distro installation initiated."
} else {
    Write-Info "Distro '$WslDistro' is already installed."
}

# -- 5. Wait for distro to become available -------------------------------------
Write-Step "Waiting for '$WslDistro' to be ready..."
$deadline = (Get-Date).AddMinutes(10)
$ready    = $false
while ((Get-Date) -lt $deadline) {
    $listing = wsl --list --verbose 2>&1 | Out-String
    if ($listing -match [regex]::Escape($WslDistro)) {
        $ready = $true; break
    }
    Start-Sleep -Seconds 5
}
if (-not $ready) {
    Abort "Timed out waiting for '$WslDistro' to appear in WSL.  Run 'wsl --install -d $WslDistro' manually."
}

# Some distros need an initial boot to finish unpacking before root is accessible
Write-Info "Performing initial WSL boot to finish unpacking..."
wsl -d $WslDistro -u root -- true 2>&1 | Out-Null
Start-Sleep -Seconds 3

# -- 6. Decrypt WSL password ----------------------------------------------------
$WslPassword = ''
if ($cfg.WslPasswordEncrypted) {
    try {
        $ss   = ConvertTo-SecureString $cfg.WslPasswordEncrypted
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
        $WslPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } catch {
        Abort "Failed to decrypt WSL password.  Re-run configure.ps1 on this machine."
    }
}

# -- 7. Create Linux user -------------------------------------------------------
Write-Step "Creating Linux user '$WslUsername'..."

$userExists = (wsl -d $WslDistro -u root -- id -u $WslUsername 2>&1) -match '^\d+$'
if (-not $userExists) {
    # Detect distro family to pick the right user-creation command and sudo group.
    # 'wheel' is used on Arch/Fedora/openSUSE; 'sudo' on Debian/Ubuntu.
    $sudoGroup = wsl -d $WslDistro -u root -- bash -c `
        "getent group sudo >/dev/null 2>&1 && echo sudo || echo wheel" 2>&1 |
        Select-Object -Last 1 | ForEach-Object { $_.Trim() }
    if (-not $sudoGroup) { $sudoGroup = 'wheel' }

    wsl -d $WslDistro -u root -- bash -c @"
bash -c '
    # adduser (Debian/Ubuntu) vs useradd (Arch, Fedora, openSUSE)
    if command -v adduser >/dev/null 2>&1 && adduser --help 2>&1 | grep -q gecos; then
        adduser --gecos "" --disabled-password "$WslUsername" 2>/dev/null || true
    else
        useradd -m -s /bin/bash "$WslUsername" 2>/dev/null || true
    fi
    echo "${WslUsername}:${WslPassword}" | chpasswd
    usermod -aG "$sudoGroup" "$WslUsername"
'
"@ 2>&1 | Out-Null
    Write-Info "User '$WslUsername' created (sudo group: $sudoGroup)."
} else {
    Write-Info "User '$WslUsername' already exists."
    # Still update password in case it changed
    wsl -d $WslDistro -u root -- bash -c "echo '${WslUsername}:${WslPassword}' | chpasswd" 2>&1 | Out-Null
}

# -- 8. Grant passwordless sudo for the installation ----------------------------
Write-Step "Granting temporary passwordless sudo for installation..."
# Write sudoers drop-in; works on all distros that ship with sudo
$sudoersLine = "${WslUsername} ALL=(ALL) NOPASSWD: ALL"
wsl -d $WslDistro -u root -- bash -c @"
bash -c '
    mkdir -p /etc/sudoers.d
    echo "$sudoersLine" > /etc/sudoers.d/ubuntu-setup-tmp
    chmod 440 /etc/sudoers.d/ubuntu-setup-tmp
    # Install sudo if somehow missing (e.g. minimal Arch/Fedora images)
    if ! command -v sudo >/dev/null 2>&1; then
        if command -v pacman >/dev/null 2>&1; then pacman -S --noconfirm --needed sudo >/dev/null 2>&1
        elif command -v dnf   >/dev/null 2>&1; then dnf install -y sudo >/dev/null 2>&1
        elif command -v zypper>/dev/null 2>&1; then zypper install -y sudo >/dev/null 2>&1
        fi
    fi
'
"@ 2>&1 | Out-Null

# -- 9. Set default WSL user via /etc/wsl.conf ---------------------------------
Write-Step "Setting default WSL user to '$WslUsername'..."
$wslConf = "[user]`ndefault=$WslUsername`n"
# Use printf to avoid CRLF from echo on some WSL versions
wsl -d $WslDistro -u root -- bash -c "printf '%s' '$wslConf' > /etc/wsl.conf" 2>&1 | Out-Null
# Terminate and restart to apply wsl.conf
wsl --terminate $WslDistro 2>&1 | Out-Null
Start-Sleep -Seconds 2

# -- 10. Write ~/.setup.conf (Bash format) inside WSL --------------------------
Write-Step "Writing Linux config (~/.setup.conf)..."

$gpgFp  = if ($cfg.GpgFingerprint) { $cfg.GpgFingerprint } else { '' }
# Force IS_INTERACTIVE=false inside WSL (VS Code and fonts live on the Windows side)
$linuxConf = @"
SETUP_HOSTNAME="$($cfg.Hostname)"
IS_INTERACTIVE="false"
GIT_NAME="$($cfg.GitName)"
GIT_EMAIL="$($cfg.GitEmail)"
GPG_FINGERPRINT="$gpgFp"
ZSH_AS_DEFAULT="$($cfg.ZshAsDefault.ToString().ToLower())"
USE_UV="$($cfg.UseUv.ToString().ToLower())"
INSTALL_PODMAN="$($cfg.InstallPodman.ToString().ToLower())"
INSTALL_RUST="$($cfg.InstallRust.ToString().ToLower())"
INSTALL_RUST_WASM="$($cfg.InstallRustWasm.ToString().ToLower())"
INSTALL_RUST_NIGHTLY="$($cfg.InstallRustNightly.ToString().ToLower())"
INSTALL_CROSS="$($cfg.InstallCross.ToString().ToLower())"
INSTALL_TYPST="$($cfg.InstallTypst.ToString().ToLower())"
INSTALL_NODEJS="$($cfg.InstallNodejs.ToString().ToLower())"
"@

# Write as a temp file on the Windows side then copy into WSL to avoid
# quoting / escaping issues with wsl -e bash -c "echo ..."
$tmpConf = Join-Path $env:TEMP 'ubuntu-setup.conf'
# Force LF line endings (critical for Bash)
[System.IO.File]::WriteAllText($tmpConf, ($linuxConf -replace "`r`n", "`n"), [System.Text.Encoding]::UTF8)

# Convert Windows path to WSL path (e.g. C:\Users\... -> /mnt/c/Users/...)
$wslTmpConf = (wsl -d $WslDistro -- wslpath -u ($tmpConf -replace '\\', '/')) | Out-String
$wslTmpConf = $wslTmpConf.Trim()

wsl -d $WslDistro -u $WslUsername -- bash -c "cp '$wslTmpConf' ~/.setup.conf && chmod 600 ~/.setup.conf" 2>&1 | Out-Null
Remove-Item $tmpConf -Force -ErrorAction SilentlyContinue
Write-Info "~/.setup.conf written."

# -- 10a. Import GPG secret key into WSL ---------------------------------------
Write-Step "Importing GPG secret key into WSL..."

$gpgKeyPath = ''
if (($cfg.PSObject.Properties['GpgKeyStaged']) -and $cfg.GpgKeyStaged -and (Test-Path $cfg.GpgKeyStaged)) {
    $gpgKeyPath = $cfg.GpgKeyStaged
} elseif ($cfg.GpgKeyFile -and (Test-Path $cfg.GpgKeyFile)) {
    $gpgKeyPath = $cfg.GpgKeyFile
}

if ($gpgKeyPath) {
    $wslGpgPath = (wsl -d $WslDistro -- wslpath -u ($gpgKeyPath -replace '\\', '/')) | Out-String
    $wslGpgPath = $wslGpgPath.Trim()
    wsl -d $WslDistro -u $WslUsername -- bash -c "gpg --batch --import '$wslGpgPath' 2>&1" 2>&1 | Out-Null
    # Mark the key with ultimate trust so it is usable immediately without prompts
    if ($cfg.GpgFingerprint) {
        $fp = $cfg.GpgFingerprint
        wsl -d $WslDistro -u $WslUsername -- bash -c "printf '%s:6:\n' '$fp' | gpg --import-ownertrust 2>&1" 2>&1 | Out-Null
    }
    Write-Info "GPG secret key imported."
} else {
    Write-Warn "No GPG key file found - skipping GPG import."
    Write-Warn "To import manually inside WSL:  gpg --import <your-key.asc>"
}

# -- 10b. Copy SSH keys from Windows into WSL ----------------------------------
Write-Step "Copying SSH keys from Windows into WSL..."

$winSshDir = Join-Path $env:USERPROFILE '.ssh'
if (Test-Path $winSshDir) {
    # Exclude Windows-only files: shortcuts, PuTTY .ppk, known_hosts.old backup
    $sshFiles = Get-ChildItem -Path $winSshDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -notin @('.lnk', '.ppk') -and $_.Name -ne 'known_hosts.old' }
    if ($sshFiles.Count -gt 0) {
        wsl -d $WslDistro -u $WslUsername -- bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh' 2>&1 | Out-Null
        foreach ($f in $sshFiles) {
            $wslSrc = (wsl -d $WslDistro -- wslpath -u ($f.FullName -replace '\\', '/')) | Out-String
            $wslSrc = $wslSrc.Trim()
            # Public files -> 644, private key files -> 600
            $mode = if ($f.Name -match '\.pub$' -or $f.Name -in @('known_hosts', 'config', 'authorized_keys')) { '644' } else { '600' }
            wsl -d $WslDistro -u $WslUsername -- bash -c "cp '$wslSrc' ~/.ssh/$($f.Name) && chmod $mode ~/.ssh/$($f.Name)" 2>&1 | Out-Null
            Write-Info "  $($f.Name)  (chmod $mode)"
        }
        Write-Info "Copied $($sshFiles.Count) SSH file(s) to WSL ~/.ssh."
    } else {
        Write-Info "No files found in Windows .ssh directory; skipping."
    }
} else {
    Write-Info "No Windows .ssh directory (~/.ssh) found; skipping SSH key copy."
}

# -- 11. Copy and run wsl_bootstrap.sh inside WSL ------------------------------
Write-Step "Running Linux bootstrap inside WSL..."

if (-not (Test-Path $WslBootstrap)) {
    Write-Warn "wsl_bootstrap.sh not found at $WslBootstrap; downloading..."
    $WslBootstrap = Join-Path $env:TEMP 'wsl_bootstrap.sh'
    try {
        Invoke-WebRequest `
            -Uri 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows/wsl_bootstrap.sh' `
            -OutFile $WslBootstrap -UseBasicParsing
    } catch {
        Abort "Failed to download wsl_bootstrap.sh: $_"
    }
}

# Ensure LF line endings (scripts fail with CRLF in WSL)
$shContent = [System.IO.File]::ReadAllText($WslBootstrap) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($WslBootstrap, $shContent, [System.Text.Encoding]::UTF8)

$wslScript = (wsl -d $WslDistro -- wslpath -u ($WslBootstrap -replace '\\', '/')) | Out-String
$wslScript = $wslScript.Trim()

wsl -d $WslDistro -u $WslUsername -- bash -c "cp '$wslScript' ~/wsl_bootstrap.sh && chmod +x ~/wsl_bootstrap.sh" 2>&1 | Out-Null

Write-Info "Starting Linux bootstrap (this may take 10-20 minutes)..."
# Run in a visible WSL window so the user can see progress
Start-Process wsl -ArgumentList @('-d', $WslDistro, '-u', $WslUsername, '--', 'bash', '-l', '~/wsl_bootstrap.sh') -Wait

# -- 12. Remove temporary passwordless sudo -------------------------------------
Write-Step "Removing temporary passwordless sudo..."
wsl -d $WslDistro -u root -- bash -c 'rm -f /etc/sudoers.d/ubuntu-setup-tmp' 2>&1 | Out-Null

# -- 13. Update phase and show completion ---------------------------------------
$cfgFinal = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Add-Member -InputObject $cfgFinal -MemberType NoteProperty -Name 'Phase' -Value 'complete' -Force
$cfgFinal | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

Write-Host ''
Write-Host '+==========================================================+' -ForegroundColor Green
Write-Host '|            ubuntu-setup for Windows - COMPLETE           |' -ForegroundColor Green
Write-Host '+==========================================================+' -ForegroundColor Green
Write-Host "|  WSL distro  : $($WslDistro.PadRight(44))|" -ForegroundColor Green
Write-Host "|  Linux user  : $($WslUsername.PadRight(44))|" -ForegroundColor Green
Write-Host '+==========================================================+' -ForegroundColor Green
Write-Host '|  To open WSL:   wsl                                      |' -ForegroundColor Green
Write-Host "|  Or open '$WslDistro' from the Start menu.              |" -ForegroundColor Green
Write-Host '+==========================================================+' -ForegroundColor Green
Write-Host ''
