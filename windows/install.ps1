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

# ── Require admin ──────────────────────────────────────────────────────────────
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

# ── Colour helpers ─────────────────────────────────────────────────────────────
function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Blue }
function Write-Info { param([string]$m) Write-Host "INFO: $m" -ForegroundColor Cyan }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Abort      { param([string]$m) Write-Host $m -ForegroundColor Red; exit 1 }

# ── Load config ────────────────────────────────────────────────────────────────
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

# ── Hostname ───────────────────────────────────────────────────────────────────
$desiredHost = $cfg.Hostname.Trim()
if ($desiredHost -and $desiredHost -ne $env:COMPUTERNAME) {
    Write-Step "Renaming computer to '$desiredHost'..."
    Rename-Computer -NewName $desiredHost -Force -ErrorAction SilentlyContinue
    Write-Info "Hostname will change after reboot."
}

# ── Git configuration ──────────────────────────────────────────────────────────
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
    Write-Warn "git not found on PATH — skipping git config."
}

# ── VS Code ────────────────────────────────────────────────────────────────────
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
            $exts = Get-Content $extFile | Where-Object { $_.Trim() -ne '' }
            $total = $exts.Count
            $i = 0
            foreach ($ext in $exts) {
                $i++
                Write-Progress -Activity "Installing VS Code extensions" -Status $ext -PercentComplete (($i / $total) * 100)
                & cmd /c "`"$codePath`" --install-extension $ext --force" 2>&1 | Out-Null
            }
            Write-Progress -Activity "Installing VS Code extensions" -Completed
            Write-Info "Installed $total extensions."
        }
    } else {
        Write-Warn "VS Code install failed or code.cmd not found.  Skipping extensions."
    }
}

# ── Fonts ──────────────────────────────────────────────────────────────────────
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

# ── WSL ────────────────────────────────────────────────────────────────────────
Write-Step "Enabling Windows Subsystem for Linux..."

$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' -ErrorAction SilentlyContinue
$wslEnabled  = $wslFeature -and $wslFeature.State -eq 'Enabled'

if (-not $wslEnabled) {
    if ($osBuild -ge 19041) {
        Write-Info "Using 'wsl --install' (Build $osBuild >= 19041)..."
        # --no-distribution: enables WSL + VM Platform without installing a distro yet
        wsl --install --no-distribution 2>&1 | Out-Null
    } else {
        Write-Info "Enabling WSL features via DISM (Build $osBuild < 19041 — WSL 1 only)..."
        Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' `
            -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' `
            -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Write-Warn "Build $osBuild supports WSL 1 only.  Update to Windows 10 2004+ for WSL 2."
    }
} else {
    Write-Info "WSL feature already enabled; skipping."
}

# ── Save phase into config ─────────────────────────────────────────────────────
$cfgObj = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Add-Member -InputObject $cfgObj -MemberType NoteProperty -Name 'Phase' -Value 'wsl-enabled' -Force
$cfgObj | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

# ── Locate wsl_resume.ps1 ─────────────────────────────────────────────────────
$WSL_RESUME = Join-Path $SCRIPT_DIR 'wsl_resume.ps1'
$RAW_BASE   = 'https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows'
if (-not (Test-Path $WSL_RESUME)) {
    Write-Info "Downloading wsl_resume.ps1..."
    $WSL_RESUME = Join-Path $env:TEMP 'wsl_resume.ps1'
    try {
        Invoke-WebRequest -Uri "$RAW_BASE/wsl_resume.ps1" -OutFile $WSL_RESUME -UseBasicParsing
    } catch {
        Abort "Failed to download wsl_resume.ps1: $_"
    }
}

# Also ensure wsl_bootstrap.sh is present alongside wsl_resume.ps1
$WSL_BOOTSTRAP = Join-Path $SCRIPT_DIR 'wsl_bootstrap.sh'
if (-not (Test-Path $WSL_BOOTSTRAP)) {
    Write-Info "Downloading wsl_bootstrap.sh..."
    $WSL_BOOTSTRAP = Join-Path $env:TEMP 'wsl_bootstrap.sh'
    try {
        Invoke-WebRequest -Uri "$RAW_BASE/wsl_bootstrap.sh" -OutFile $WSL_BOOTSTRAP -UseBasicParsing
    } catch {
        Write-Warn "Failed to download wsl_bootstrap.sh: $_"
    }
}

# Store wsl_resume and bootstrap paths into config so wsl_resume.ps1 can find them
$cfgObj2 = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Add-Member -InputObject $cfgObj2 -MemberType NoteProperty -Name 'WslResumeScript'    -Value $WSL_RESUME    -Force
Add-Member -InputObject $cfgObj2 -MemberType NoteProperty -Name 'WslBootstrapScript' -Value $WSL_BOOTSTRAP -Force
$cfgObj2 | ConvertTo-Json -Depth 4 | Set-Content $ConfigFile -Encoding UTF8

# ── Register post-reboot scheduled task ────────────────────────────────────────
Write-Step "Registering post-reboot scheduled task (ubuntu-setup-wsl-resume)..."

$taskName = 'ubuntu-setup-wsl-resume'
# Remove any stale registration
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ("-ExecutionPolicy Bypass -NoProfile -WindowStyle Normal " +
               "-File `"$WSL_RESUME`" -ConfigFile `"$ConfigFile`"")

# Trigger: at logon of the current (non-elevated) user
# We identify the real logged-on user because this script runs elevated
$loggedOnUser = (Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if (-not $loggedOnUser) { $loggedOnUser = "$env:USERDOMAIN\$env:USERNAME" }

$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $loggedOnUser
$principal = New-ScheduledTaskPrincipal -UserId $loggedOnUser -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -DisallowDemandStart $false `
    -RestartCount 0

Register-ScheduledTask `
    -TaskName  $taskName `
    -Action    $action `
    -Trigger   $trigger `
    -Principal $principal `
    -Settings  $settings `
    -Force | Out-Null

Write-Info "Scheduled task '$taskName' registered."

# ── Countdown and reboot ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  WSL has been enabled.  A reboot is required.' -ForegroundColor Yellow
Write-Host '  After reboot, the setup will continue automatically.' -ForegroundColor Yellow
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

for ($s = 10; $s -ge 1; $s--) {
    Write-Host "`r  Rebooting in $s second(s)...  Press Ctrl+C to cancel." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ''

} finally {
    Cleanup
}

Restart-Computer -Force
