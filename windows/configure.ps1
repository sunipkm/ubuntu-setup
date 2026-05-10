#Requires -Version 5.1
#Requires -STA
<#
.SYNOPSIS
    WinForms configuration wizard for the Windows ubuntu-setup port.
    Equivalent to configure.sh on Linux/macOS.

.DESCRIPTION
    Presents a multi-page GUI wizard that collects installation preferences
    and writes them to a JSON config file consumed by install.ps1.

.PARAMETER ConfigFile
    Path to write the output JSON config (default: $env:USERPROFILE\.setup-windows.json).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -STA -File .\configure.ps1
    powershell -ExecutionPolicy Bypass -STA -File .\configure.ps1 -ConfigFile C:\my-config.json
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $env:USERPROFILE '.setup-windows.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Load WinForms --------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# -- Helper: create a Label -----------------------------------------------------
function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 520, [int]$H = 22,
          [float]$FontSize = 9.0, [System.Drawing.FontStyle]$Style = 'Regular')
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $Text
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size     = New-Object System.Drawing.Size($W, $H)
    $lbl.Font     = New-Object System.Drawing.Font('Segoe UI', $FontSize, $Style)
    $lbl.AutoSize = $false
    return $lbl
}

# -- Helper: create a TextBox ---------------------------------------------------
function New-TextBox {
    param([string]$Text = '', [int]$X, [int]$Y, [int]$W = 500, [bool]$Password = $false)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text     = $Text
    $tb.Location = New-Object System.Drawing.Point($X, $Y)
    $tb.Size     = New-Object System.Drawing.Size($W, 24)
    if ($Password) { $tb.PasswordChar = [char]0x2022 }
    return $tb
}

# -- Get available WSL distros --------------------------------------------------
function Get-WslDistros {
    $fallback = @('Ubuntu-24.04','Ubuntu-22.04','Ubuntu-20.04','Ubuntu','Debian')
    try {
        $raw = & wsl --list --online 2>&1 | Out-String
        # Output has a header block of ~4 lines before the table
        $lines = $raw -split "`n" | Where-Object { $_ -match '^\s*\S' }
        # Find the line with "NAME" header and take everything after
        $headerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^NAME') { $headerIdx = $i; break }
        }
        if ($headerIdx -ge 0) {
            $distros = $lines[($headerIdx + 1)..($lines.Count - 1)] | ForEach-Object {
                # Each line: "Ubuntu-24.04    Ubuntu 24.04 LTS"
                ($_ -split '\s{2,}')[0].Trim()
            } | Where-Object { $_ -ne '' -and $_ -notmatch '^-' }
            if ($distros.Count -gt 0) { return $distros }
        }
    } catch { }
    return $fallback
}

# -- WSL distro list (fetched once) --------------------------------------------
$availableDistros = Get-WslDistros

# -- Storage for collected values -----------------------------------------------
$cfg = @{
    Phase              = 'configured'
    Hostname           = $env:COMPUTERNAME
    GitName            = ''
    GitEmail           = ''
    GpgKeyFile         = ''
    GpgFingerprint     = ''
    IsInteractive      = $true
    WslDistro          = 'Ubuntu-24.04'
    WslUsername        = ''
    WslPasswordEncrypted = ''
    InstallRust        = $false
    InstallRustWasm    = $false
    InstallRustNightly = $false
    InstallCross       = $false
    InstallNodejs      = $false
    InstallPodman      = $false
    InstallTypst       = $false
    UseUv              = $true
    ZshAsDefault       = $true
    ScriptDir          = (Split-Path -Parent $PSCommandPath -ErrorAction SilentlyContinue)
    ConfigFile         = $ConfigFile
}

# ==============================================================================
# Wizard form
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'ubuntu-setup - Windows Configuration Wizard'
$form.Size            = New-Object System.Drawing.Size(620, 560)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false

# Title bar
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object System.Drawing.Point(12, 10)
$lblTitle.Size     = New-Object System.Drawing.Size(580, 30)
$lblTitle.Font     = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

$sepTop = New-Object System.Windows.Forms.Label
$sepTop.BorderStyle = 'Fixed3D'
$sepTop.Location    = New-Object System.Drawing.Point(12, 44)
$sepTop.Size        = New-Object System.Drawing.Size(580, 2)
$form.Controls.Add($sepTop)

# Content panel
$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Location = New-Object System.Drawing.Point(12, 52)
$pnlContent.Size     = New-Object System.Drawing.Size(580, 420)
$pnlContent.AutoScroll = $true
$form.Controls.Add($pnlContent)

# Bottom separator
$sepBot = New-Object System.Windows.Forms.Label
$sepBot.BorderStyle = 'Fixed3D'
$sepBot.Location    = New-Object System.Drawing.Point(12, 476)
$sepBot.Size        = New-Object System.Drawing.Size(580, 2)
$form.Controls.Add($sepBot)

# Navigation buttons
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text     = 'Cancel'
$btnCancel.Location = New-Object System.Drawing.Point(12, 490)
$btnCancel.Size     = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnCancel)

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text     = '< Back'
$btnBack.Location = New-Object System.Drawing.Point(408, 490)
$btnBack.Size     = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnBack)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text     = 'Next >'
$btnNext.Location = New-Object System.Drawing.Point(505, 490)
$btnNext.Size     = New-Object System.Drawing.Size(90, 30)
$form.AcceptButton = $btnNext
$form.Controls.Add($btnNext)

# ==============================================================================
# Page panels
# ==============================================================================
$pages      = [System.Collections.ArrayList]::new()
$pageTitles = [System.Collections.ArrayList]::new()
$currentPageIdx = 0

function Add-Page {
    param([string]$Title, [System.Windows.Forms.Panel]$Panel)
    $Panel.Dock    = 'Fill'
    $Panel.Visible = $false
    $pnlContent.Controls.Add($Panel)
    [void]$pages.Add($Panel)
    [void]$pageTitles.Add($Title)
}

# -- Page 0: Welcome ------------------------------------------------------------
$p0 = New-Object System.Windows.Forms.Panel
$p0.Controls.Add((New-Label -Text 'Welcome to ubuntu-setup for Windows!' -X 0 -Y 10 -FontSize 12 -Style Bold))
$p0.Controls.Add((New-Label -Text (
    "This wizard collects your installation preferences and writes them to:`n`n" +
    "  $ConfigFile`n`n" +
    "That file is then passed to install.ps1 for a fully unattended install.`n`n" +
    "What will be configured:`n" +
    "  * Visual Studio Code + all extensions from extensions.txt`n" +
    "  * Nerd Fonts (CascadiaCode, Meslo) + Microsoft Aptos fonts`n" +
    "  * Windows Subsystem for Linux (WSL 2) with your chosen distro`n" +
    "  * Full Linux developer environment inside WSL (dotfiles, Python,`n" +
    "    oh-my-zsh, starship, tmux, and more)`n`n" +
    "Click Next to begin."
) -X 0 -Y 50 -H 320))
Add-Page -Title 'Welcome' -Panel $p0

# -- Page 1: Hostname -----------------------------------------------------------
$p1 = New-Object System.Windows.Forms.Panel
$p1.Controls.Add((New-Label -Text 'Desired hostname for this machine:' -X 0 -Y 10))
$p1.Controls.Add((New-Label -Text '(Leave blank to keep current hostname)' -X 0 -Y 32 -FontSize 8.5))
$p1_tbHostname = New-TextBox -Text $env:COMPUTERNAME -X 0 -Y 58
$p1.Controls.Add($p1_tbHostname)
Add-Page -Title 'Hostname' -Panel $p1

# -- Page 2: Git identity -------------------------------------------------------
$p2 = New-Object System.Windows.Forms.Panel
$p2.Controls.Add((New-Label -Text 'Git user name:' -X 0 -Y 10))
$p2_tbName = New-TextBox -X 0 -Y 32
$p2.Controls.Add($p2_tbName)
$p2.Controls.Add((New-Label -Text 'Git email address:' -X 0 -Y 72))
$p2_tbEmail = New-TextBox -X 0 -Y 94
$p2.Controls.Add($p2_tbEmail)

$p2.Controls.Add((New-Label -Text 'GPG secret key (optional):' -X 0 -Y 138))
$p2.Controls.Add((New-Label -Text (
    "Select an exported .asc or .gpg key file. The key will be imported to pre-fill" +
    " name/email and enable signed git commits."
) -X 0 -Y 158 -H 36 -FontSize 8.5))
$p2_tbGpg = New-TextBox -X 0 -Y 198 -W 420
$p2_tbGpg.ReadOnly = $true
$p2.Controls.Add($p2_tbGpg)

$btnBrowseGpg = New-Object System.Windows.Forms.Button
$btnBrowseGpg.Text     = 'Browse...'
$btnBrowseGpg.Location = New-Object System.Drawing.Point(426, 197)
$btnBrowseGpg.Size     = New-Object System.Drawing.Size(80, 26)
$p2.Controls.Add($btnBrowseGpg)

$btnBrowseGpg.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title  = 'Select GPG secret key file'
    $ofd.Filter = 'GPG key files (*.asc;*.gpg)|*.asc;*.gpg|All files (*.*)|*.*'
    if ($ofd.ShowDialog() -eq 'OK') {
        $p2_tbGpg.Text = $ofd.FileName
        # Try to import and extract uid
        $gpgCmd = Get-Command gpg -ErrorAction SilentlyContinue
        $gpgExe = if ($gpgCmd) { $gpgCmd.Source } else { $null }
        if (-not $gpgExe) {
            foreach ($p in @(
                "$env:ProgramFiles\Git\usr\bin\gpg.exe",
                "$env:LOCALAPPDATA\Programs\Git\usr\bin\gpg.exe"
            )) { if (Test-Path $p) { $gpgExe = $p; break } }
        }
        if ($gpgExe) {
            try {
                & $gpgExe --import $ofd.FileName 2>&1 | Out-Null
                $uid = (& $gpgExe --list-secret-keys --with-colons 2>&1 |
                    Where-Object { $_ -match '^uid' } |
                    Select-Object -First 1) -split ':'
                # colon format uid field is at index 9: "Name <email>"
                if ($uid.Count -ge 10) {
                    $raw = $uid[9]
                    if ($raw -match '^(.+?)\s*<(.+)>$') {
                        if (-not $p2_tbName.Text)  { $p2_tbName.Text  = $Matches[1].Trim() }
                        if (-not $p2_tbEmail.Text) { $p2_tbEmail.Text = $Matches[2].Trim() }
                    }
                }
                $fp = (& $gpgExe --list-secret-keys --with-colons 2>&1 |
                    Where-Object { $_ -match '^fpr' } |
                    Select-Object -First 1) -split ':'
                if ($fp.Count -ge 10) { $cfg.GpgFingerprint = $fp[9].Trim() }
            } catch { }
        }
    }
})
Add-Page -Title 'Git Identity' -Panel $p2

# -- Page 3: System type --------------------------------------------------------
$p3 = New-Object System.Windows.Forms.Panel
$p3.Controls.Add((New-Label -Text 'System type:' -X 0 -Y 10))
$p3.Controls.Add((New-Label -Text (
    "Interactive (desktop/laptop): installs VS Code, Nerd Fonts, and desktop extras.`n" +
    "Headless (server): core tools only - no GUI applications or fonts."
) -X 0 -Y 32 -H 48 -FontSize 8.5))

$p3_rbInteractive = New-Object System.Windows.Forms.RadioButton
$p3_rbInteractive.Text     = 'Interactive (desktop / laptop)'
$p3_rbInteractive.Location = New-Object System.Drawing.Point(0, 92)
$p3_rbInteractive.Size     = New-Object System.Drawing.Size(300, 24)
$p3_rbInteractive.Checked  = $true
$p3.Controls.Add($p3_rbInteractive)

$p3_rbHeadless = New-Object System.Windows.Forms.RadioButton
$p3_rbHeadless.Text     = 'Headless (server - core tools only)'
$p3_rbHeadless.Location = New-Object System.Drawing.Point(0, 122)
$p3_rbHeadless.Size     = New-Object System.Drawing.Size(320, 24)
$p3.Controls.Add($p3_rbHeadless)
Add-Page -Title 'System Type' -Panel $p3

# -- Page 4: WSL distro --------------------------------------------------------
$p4 = New-Object System.Windows.Forms.Panel
$p4.Controls.Add((New-Label -Text 'Choose WSL Linux distribution:' -X 0 -Y 10))
$p4.Controls.Add((New-Label -Text (
    "The selected distro will be installed in WSL 2 (or WSL 1 on older builds).`n" +
    "Ubuntu 24.04 LTS is recommended for maximum compatibility with this setup."
) -X 0 -Y 32 -H 40 -FontSize 8.5))

$p4_lstDistro = New-Object System.Windows.Forms.ListBox
$p4_lstDistro.Location     = New-Object System.Drawing.Point(0, 80)
$p4_lstDistro.Size         = New-Object System.Drawing.Size(400, 200)
$p4_lstDistro.SelectionMode = 'One'
foreach ($d in $availableDistros) { [void]$p4_lstDistro.Items.Add($d) }
$p4_lstDistro.SelectedIndex = 0
$p4.Controls.Add($p4_lstDistro)
Add-Page -Title 'WSL Distribution' -Panel $p4

# -- Page 5: WSL credentials ---------------------------------------------------
$p5 = New-Object System.Windows.Forms.Panel
$p5.Controls.Add((New-Label -Text 'Linux username (for WSL):' -X 0 -Y 10))
$p5.Controls.Add((New-Label -Text 'Lowercase letters, digits, hyphens only (e.g. john, dev-user).' -X 0 -Y 32 -FontSize 8.5))
$p5_tbUser = New-TextBox -X 0 -Y 54
$p5.Controls.Add($p5_tbUser)

$p5.Controls.Add((New-Label -Text 'Linux password:' -X 0 -Y 94))
$p5_tbPass = New-TextBox -X 0 -Y 116 -Password $true
$p5.Controls.Add($p5_tbPass)

$p5.Controls.Add((New-Label -Text 'Confirm password:' -X 0 -Y 156))
$p5_tbPass2 = New-TextBox -X 0 -Y 178 -Password $true
$p5.Controls.Add($p5_tbPass2)

$p5_lblErr = New-Label -Text '' -X 0 -Y 218 -FontSize 9
$p5_lblErr.ForeColor = [System.Drawing.Color]::Red
$p5.Controls.Add($p5_lblErr)
Add-Page -Title 'WSL Credentials' -Panel $p5

# -- Page 6: Optional components -----------------------------------------------
$p6 = New-Object System.Windows.Forms.Panel
$p6.Controls.Add((New-Label -Text 'Optional components (installed inside WSL):' -X 0 -Y 10))

$chkDefs = @(
    @{ Name='chkRust';    Text='Rust toolchain (rustup)';                    Y=44;  Key='InstallRust'    }
    @{ Name='chkWasm';    Text='  + Rust WASM target (wasm32-unknown-unknown)'; Y=68;  Key='InstallRustWasm' }
    @{ Name='chkNightly'; Text='  + Rust nightly toolchain';                Y=92;  Key='InstallRustNightly' }
    @{ Name='chkCross';   Text='  + cross (cross-compilation, needs Podman)'; Y=116; Key='InstallCross'   }
    @{ Name='chkNode';    Text='Node.js LTS via nvm';                        Y=148; Key='InstallNodejs'  }
    @{ Name='chkPodman';  Text='Podman (container engine)';                  Y=172; Key='InstallPodman'  }
    @{ Name='chkTypst';   Text='Typst (document compiler, needs Rust)';      Y=196; Key='InstallTypst'   }
)

$p6_checks = @{}
foreach ($def in $chkDefs) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text     = $def.Text
    $chk.Location = New-Object System.Drawing.Point(12, $def.Y)
    $chk.Size     = New-Object System.Drawing.Size(520, 22)
    $p6.Controls.Add($chk)
    $p6_checks[$def.Key] = $chk
}

$p6.Controls.Add((New-Label -Text 'Python package manager (inside WSL):' -X 0 -Y 234))
$p6_rbUv = New-Object System.Windows.Forms.RadioButton
$p6_rbUv.Text     = 'uv  (fast, modern - recommended)'
$p6_rbUv.Location = New-Object System.Drawing.Point(12, 256)
$p6_rbUv.Size     = New-Object System.Drawing.Size(300, 22)
$p6_rbUv.Checked  = $true
$p6.Controls.Add($p6_rbUv)

$p6_rbConda = New-Object System.Windows.Forms.RadioButton
$p6_rbConda.Text     = 'Miniconda3 (conda environments)'
$p6_rbConda.Location = New-Object System.Drawing.Point(12, 280)
$p6_rbConda.Size     = New-Object System.Drawing.Size(300, 22)
$p6.Controls.Add($p6_rbConda)

Add-Page -Title 'Optional Components' -Panel $p6

# -- Page 7: Summary -----------------------------------------------------------
$p7 = New-Object System.Windows.Forms.Panel
$p7.Controls.Add((New-Label -Text 'Review your configuration:' -X 0 -Y 10))

$p7_tbSummary = New-Object System.Windows.Forms.TextBox
$p7_tbSummary.Location  = New-Object System.Drawing.Point(0, 36)
$p7_tbSummary.Size      = New-Object System.Drawing.Size(560, 330)
$p7_tbSummary.Multiline = $true
$p7_tbSummary.ScrollBars = 'Vertical'
$p7_tbSummary.ReadOnly  = $true
$p7_tbSummary.Font      = New-Object System.Drawing.Font('Consolas', 9)
$p7_tbSummary.BackColor = [System.Drawing.SystemColors]::Window
$p7.Controls.Add($p7_tbSummary)
Add-Page -Title 'Summary' -Panel $p7

# ==============================================================================
# Navigation logic
# ==============================================================================
function Collect-CurrentPage {
    # Harvest values from the currently-visible page before moving away
    switch ($script:currentPageIdx) {
        1 { $script:cfg.Hostname  = $p1_tbHostname.Text.Trim() }
        2 {
            $script:cfg.GitName   = $p2_tbName.Text.Trim()
            $script:cfg.GitEmail  = $p2_tbEmail.Text.Trim()
            $script:cfg.GpgKeyFile= $p2_tbGpg.Text.Trim()
        }
        3 { $script:cfg.IsInteractive = $p3_rbInteractive.Checked }
        4 {
            if ($p4_lstDistro.SelectedItem) {
                $script:cfg.WslDistro = $p4_lstDistro.SelectedItem.ToString()
            }
        }
        5 {
            $script:cfg.WslUsername = $p5_tbUser.Text.Trim()
            # Encrypt password with DPAPI (user-key, survives reboot for same user)
            if ($p5_tbPass.Text.Length -gt 0) {
                $ss = New-Object System.Security.SecureString
                foreach ($c in $p5_tbPass.Text.ToCharArray()) { $ss.AppendChar($c) }
                $script:cfg.WslPasswordEncrypted = ConvertFrom-SecureString $ss
                $ss.Dispose()
            }
        }
        6 {
            foreach ($key in $p6_checks.Keys) {
                $script:cfg[$key] = $p6_checks[$key].Checked
            }
            $script:cfg.UseUv = $p6_rbUv.Checked
        }
    }
}

function Validate-CurrentPage {
    switch ($script:currentPageIdx) {
        5 {
            $u = $p5_tbUser.Text.Trim()
            if ($u -notmatch '^[a-z][a-z0-9\-]{0,30}$') {
                $p5_lblErr.Text = 'Username must start with a lowercase letter and contain only a-z, 0-9, -'
                return $false
            }
            if ($p5_tbPass.Text.Length -lt 6) {
                $p5_lblErr.Text = 'Password must be at least 6 characters.'
                return $false
            }
            if ($p5_tbPass.Text -ne $p5_tbPass2.Text) {
                $p5_lblErr.Text = 'Passwords do not match.'
                return $false
            }
            $p5_lblErr.Text = ''
        }
    }
    return $true
}

function Build-Summary {
    $lines = @(
        "Hostname       : $($script:cfg.Hostname)"
        "Git name       : $($script:cfg.GitName)"
        "Git email      : $($script:cfg.GitEmail)"
        "GPG key        : $(if ($script:cfg.GpgKeyFile) { $script:cfg.GpgKeyFile } else { '(none)' })"
        "System type    : $(if ($script:cfg.IsInteractive) { 'Interactive (desktop)' } else { 'Headless (server)' })"
        "WSL distro     : $($script:cfg.WslDistro)"
        "WSL username   : $($script:cfg.WslUsername)"
        "Python backend : $(if ($script:cfg.UseUv) { 'uv' } else { 'Miniconda3' })"
        ''
        'Optional components:'
        "  Rust toolchain    : $($script:cfg.InstallRust)"
        "  Rust WASM target  : $($script:cfg.InstallRustWasm)"
        "  Rust nightly      : $($script:cfg.InstallRustNightly)"
        "  cross             : $($script:cfg.InstallCross)"
        "  Node.js (nvm)     : $($script:cfg.InstallNodejs)"
        "  Podman            : $($script:cfg.InstallPodman)"
        "  Typst             : $($script:cfg.InstallTypst)"
        ''
        "Config will be saved to:`n  $($script:cfg.ConfigFile)"
    )
    return $lines -join "`r`n"
}

function Show-Page {
    param([int]$Index)
    for ($i = 0; $i -lt $pages.Count; $i++) {
        $pages[$i].Visible = ($i -eq $Index)
    }
    $lblTitle.Text        = $pageTitles[$Index]
    $btnBack.Enabled      = ($Index -gt 0)
    $script:currentPageIdx = $Index
    $isLast = ($Index -eq ($pages.Count - 1))
    $btnNext.Text = if ($isLast) { 'Save & Install' } else { 'Next >' }
    if ($isLast) { $p7_tbSummary.Text = Build-Summary }
}

# -- Button handlers ------------------------------------------------------------
$btnNext.Add_Click({
    if (-not (Validate-CurrentPage)) { return }
    Collect-CurrentPage
    $next = $script:currentPageIdx + 1
    if ($next -ge $pages.Count) {
        # Reached beyond last page -> save and close
        Save-Config
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    } else {
        Show-Page -Index $next
    }
})

$btnBack.Add_Click({
    Collect-CurrentPage
    $prev = $script:currentPageIdx - 1
    if ($prev -ge 0) { Show-Page -Index $prev }
})

$btnCancel.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

# -- Save config to JSON --------------------------------------------------------
function Save-Config {
    $json = $script:cfg | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:cfg.ConfigFile, $json, [System.Text.Encoding]::UTF8)
    Write-Host "Configuration saved to: $($script:cfg.ConfigFile)" -ForegroundColor Green
}

# -- Show first page and run ----------------------------------------------------
try {
    Show-Page -Index 0
    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
    exit 0
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "An unexpected error occurred:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)",
        'ubuntu-setup - Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
