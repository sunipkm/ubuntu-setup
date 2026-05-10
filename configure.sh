#!/usr/bin/env bash
# configure.sh - dialog-based TUI that collects all install preferences and
# writes them to a sourceable shell config file (default: ~/.setup.conf).
#
# Usage:
#   bash configure.sh [OUTPUT_FILE]
#   bash configure.sh ~/.setup.conf
#
# The generated file is sourced by bootstrap.sh (--config flag) to run
# a fully unattended install.

# -- Prerequisites --------------------------------------------------------------
if ! command -v dialog &>/dev/null; then
    echo "Error: 'dialog' is not installed." >&2
    echo "" >&2
    echo "Install it first:" >&2
    echo "  Debian/Ubuntu : sudo apt-get install dialog" >&2
    echo "  Arch Linux    : sudo pacman -S dialog" >&2
    echo "  Fedora        : sudo dnf install dialog" >&2
    echo "  macOS         : brew install dialog" >&2
    exit 1
fi

CONFIG_FILE="${1:-$HOME/.setup.conf}"

# Scratch files for capturing dialog output
TMP=$(mktemp)
SUMMARY_FILE=$(mktemp)
trap 'rm -f "$TMP" "$SUMMARY_FILE"; clear' EXIT

PLATFORM=$(uname -s)

# -- Helper: show an error box --------------------------------------------------
d_error() {
    dialog --title "Error" --msgbox "$1" 10 62
}

# -- Helper: test whether TAG appears in dialog checklist output ----------------
# dialog emits tags as space-separated bare or quoted words, e.g.:
#   PODMAN "RUST" NODEJS
# grep -w treats _ as a word character, so RUST won't match RUST_WASM.
selected() {
    local tag="$1" output="$2"
    echo "$output" | grep -qw "$tag"
}

# -- Welcome --------------------------------------------------------------------
dialog --backtitle "ubuntu-setup configurator" \
    --title " Welcome " \
    --msgbox "\
This wizard collects your install preferences and writes them to:\n\
\n\
  $CONFIG_FILE\n\
\n\
That file can be passed to bootstrap.sh (--config) for a fully\n\
unattended install, or used to reproduce this environment later.\n\
\n\
Navigate with Tab / arrow keys.  Space toggles checkboxes." \
    14 66

# -- Hostname -------------------------------------------------------------------
CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo "")
dialog --backtitle "ubuntu-setup configurator" \
    --title " Hostname " \
    --inputbox \
    "Desired hostname for this machine.\n(Leave blank to keep current: ${CURRENT_HOSTNAME})" \
    9 66 "$CURRENT_HOSTNAME" 2>"$TMP"
SETUP_HOSTNAME=$(cat "$TMP")
[[ -z "$SETUP_HOSTNAME" ]] && SETUP_HOSTNAME="$CURRENT_HOSTNAME"

# -- System type ----------------------------------------------------------------
IS_INTERACTIVE=false
dialog --backtitle "ubuntu-setup configurator" \
    --title " System Type " \
    --yesno \
"Is this an interactive (desktop / laptop) system?\n\
\n\
YES -> installs a terminal emulator (kitty), nerd fonts,\n\
      VS Code GUI, and other desktop extras.\n\
NO  -> headless / server setup only." \
    11 66 && IS_INTERACTIVE=true

# -- GPG identity (asked first - extracts git name/email from key UID) ----------
GPG_IMPORT=false
GPG_KEY_FILE=""
GPG_FINGERPRINT=""
GIT_NAME=""
GIT_EMAIL=""

dialog --backtitle "ubuntu-setup configurator" \
    --title " GPG Identity " \
    --yesno \
"Import a GPG secret key?\n\
\n\
The key is imported now to:\n\
  - pre-fill your git name and email from the key UID\n\
  - configure git to sign commits automatically\n\
\n\
You will be asked for the path to your exported .asc / .gpg file." \
    13 66 && GPG_IMPORT=true

if $GPG_IMPORT; then
    while true; do
        dialog --backtitle "ubuntu-setup configurator" \
            --title " GPG Key File " \
            --inputbox \
"Path to your exported GPG secret-key file (.asc or .gpg):\n\
(Leave blank to skip GPG import)" \
            10 72 "${GPG_KEY_FILE:-$HOME/}" 2>"$TMP"
        GPG_KEY_FILE=$(cat "$TMP")
        GPG_KEY_FILE="${GPG_KEY_FILE/#\~/$HOME}"
        if [[ -z "$GPG_KEY_FILE" ]]; then
            GPG_IMPORT=false
            break
        elif [[ -f "$GPG_KEY_FILE" ]]; then
            break
        else
            d_error "File not found:\n\n  $GPG_KEY_FILE\n\nEnter a valid path, or leave blank to skip."
        fi
    done
fi

if $GPG_IMPORT; then
    if gpg --batch --import "$GPG_KEY_FILE" 2>/dev/null; then
        GPG_FINGERPRINT=$(gpg --list-secret-keys --with-colons 2>/dev/null \
            | awk -F: '/^fpr/{print $10; exit}')
        if [[ -n "$GPG_FINGERPRINT" ]]; then
            _GPG_UID=$(gpg --list-secret-keys --with-colons "$GPG_FINGERPRINT" 2>/dev/null \
                | awk -F: '/^uid/{print $10; exit}')
            GIT_NAME=$(echo "$_GPG_UID"  | sed 's/ <.*//')
            GIT_EMAIL=$(echo "$_GPG_UID" | sed 's/.*<\(.*\)>/\1/')
            # Configure git now - no reason to defer to install.sh
            git config --global user.name        "$GIT_NAME"
            git config --global user.email       "$GIT_EMAIL"
            git config --global user.signingkey  "$GPG_FINGERPRINT"
            git config --global commit.gpgsign   true
            git config --global init.defaultBranch master 2>/dev/null || true
            dialog --backtitle "ubuntu-setup configurator" \
                --title " GPG Identity " \
                --msgbox \
"GPG key imported successfully.\n\
\n\
Identity    : $_GPG_UID\n\
Fingerprint : $GPG_FINGERPRINT\n\
\n\
Git configured:\n\
  user.name       = $GIT_NAME\n\
  user.email      = $GIT_EMAIL\n\
  user.signingkey = $GPG_FINGERPRINT\n\
  commit.gpgsign  = true" \
                17 72
        else
            d_error "GPG import succeeded but no secret key was found.\nGit name/email must be entered manually."
            GPG_IMPORT=false
            GPG_FINGERPRINT=""
        fi
    else
        d_error "GPG import failed.\nCheck that the file is a valid exported secret key.\nGit name/email must be entered manually."
        GPG_IMPORT=false
    fi
fi

# -- Git configuration (skipped if GPG import provided name + email) ------------
if ! $GPG_IMPORT || [[ -z "$GIT_NAME" ]] || [[ -z "$GIT_EMAIL" ]]; then
    _PRE_NAME=$(git config --global user.name  2>/dev/null || true)
    _PRE_EMAIL=$(git config --global user.email 2>/dev/null || true)
    [[ -n "$GIT_NAME"  ]] || GIT_NAME="$_PRE_NAME"
    [[ -n "$GIT_EMAIL" ]] || GIT_EMAIL="$_PRE_EMAIL"

    dialog --backtitle "ubuntu-setup configurator" \
        --title " Git - Full Name " \
        --inputbox "Your full name used in git commits:" \
        8 60 "$GIT_NAME" 2>"$TMP"
    GIT_NAME=$(cat "$TMP")

    dialog --backtitle "ubuntu-setup configurator" \
        --title " Git - Email " \
        --inputbox "Your email address used in git commits:" \
        8 60 "$GIT_EMAIL" 2>"$TMP"
    GIT_EMAIL=$(cat "$TMP")

    # Apply git config now (no GPG signing since no key was imported)
    [[ -n "$GIT_NAME"  ]] && git config --global user.name  "$GIT_NAME"
    [[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"
    git config --global init.defaultBranch master 2>/dev/null || true
fi

# -- SSH keys -------------------------------------------------------------------
SSH_COPY=false
SSH_SRC_DIR=""
SSH_GENERATE=false

# Step 1: offer to copy from an existing directory
dialog --backtitle "ubuntu-setup configurator" \
    --title " SSH Keys - Import " \
    --yesno \
"Copy SSH keys from an existing directory?\n\
\n\
Copies: id_* key pairs, *.pub files, config,\n\
        authorized_keys, and known_hosts." \
    10 62 && SSH_COPY=true

if $SSH_COPY; then
    while true; do
        dialog --backtitle "ubuntu-setup configurator" \
            --title " SSH Source Directory " \
            --inputbox \
"Path to the directory containing your SSH keys:\n\
(Leave blank to skip)" \
            10 72 "${SSH_SRC_DIR:-$HOME/.ssh}" 2>"$TMP"
        SSH_SRC_DIR=$(cat "$TMP")
        SSH_SRC_DIR="${SSH_SRC_DIR/#\~/$HOME}"
        if [[ -z "$SSH_SRC_DIR" ]]; then
            SSH_COPY=false
            break
        elif [[ -d "$SSH_SRC_DIR" ]]; then
            # Copy the keys now so we can detect if id_ed25519 is present
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            for _f in "$SSH_SRC_DIR"/id_* "$SSH_SRC_DIR"/*.pub \
                       "$SSH_SRC_DIR/config" "$SSH_SRC_DIR/authorized_keys" \
                       "$SSH_SRC_DIR/known_hosts"; do
                [[ -f "$_f" ]] || continue
                cp "$_f" "$HOME/.ssh/$(basename "$_f")"
            done
            for _f in "$HOME/.ssh"/id_*; do
                [[ -f "$_f" && "$_f" != *.pub ]] && chmod 600 "$_f"
            done
            chmod 644 "$HOME/.ssh"/*.pub "$HOME/.ssh/config" \
                       "$HOME/.ssh/authorized_keys" "$HOME/.ssh/known_hosts" 2>/dev/null
            break
        else
            d_error "Directory not found:\n\n  $SSH_SRC_DIR\n\nEnter a valid path, or leave blank to skip."
        fi
    done
fi

# Step 2: generate a new ed25519 key only if none exists
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    dialog --backtitle "ubuntu-setup configurator" \
        --title " SSH Keys \u2014 Generate " \
        --yesno \
"No ed25519 key found at ~/.ssh/id_ed25519.\n\
\n\
Generate a new SSH key now?\n\
(You will be asked to set a passphrase; leave blank for none.)" \
        10 62 && SSH_GENERATE=true

    if $SSH_GENERATE; then
        # Collect + confirm passphrase via passwordbox
        while true; do
            dialog --backtitle "ubuntu-setup configurator" \
                --title " SSH Key Passphrase " \
                --passwordbox \
"Enter a passphrase for the new SSH key.\n\
(Leave blank for no passphrase.)" \
                9 62 2>"$TMP"
            _SSH_PASS1=$(cat "$TMP")

            dialog --backtitle "ubuntu-setup configurator" \
                --title " SSH Key Passphrase - Confirm " \
                --passwordbox "Re-enter the passphrase to confirm:" \
                8 62 2>"$TMP"
            _SSH_PASS2=$(cat "$TMP")

            if [[ "$_SSH_PASS1" == "$_SSH_PASS2" ]]; then
                break
            else
                d_error "Passphrases do not match. Please try again."
            fi
        done

        _SSH_COMMENT="${GIT_EMAIL:-$(whoami)@$(hostname)}"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 \
                   -C "$_SSH_COMMENT" \
                   -N "$_SSH_PASS1" \
                   -f "$HOME/.ssh/id_ed25519" </dev/null

        if [[ $? -eq 0 ]]; then
            _PUBKEY=$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)
            dialog --backtitle "ubuntu-setup configurator" \
                --title " SSH Key Generated " \
                --msgbox \
"New SSH key created: ~/.ssh/id_ed25519\n\
\n\
Public key:\n\
  $_PUBKEY\n\
\n\
Add this to GitHub / GitLab / remote servers." \
                14 76
        else
            d_error "ssh-keygen failed.\nYou can generate a key manually later:\n  ssh-keygen -t ed25519"
            SSH_GENERATE=false
        fi
        unset _SSH_PASS1 _SSH_PASS2   # don't leave passphrase in memory
    fi
fi

# -- Default shell -------------------------------------------------------------
ZSH_AS_DEFAULT=false
dialog --backtitle "ubuntu-setup configurator" \
    --title " Default Shell " \
    --yesno \
"Set zsh as your default login shell?\n\
(Runs: chsh -s \$(which zsh))" \
    8 54 && ZSH_AS_DEFAULT=true

# -- Python backend -------------------------------------------------------------
dialog --backtitle "ubuntu-setup configurator" \
    --title " Python Backend " \
    --menu \
"Choose a Python installation method:" \
    11 60 2 \
    "MINICONDA" "Miniconda3  (stable, recommended)" \
    "UV"        "uv          (experimental, faster)" \
    2>"$TMP"
PY_BACKEND=$(cat "$TMP")
[[ -z "$PY_BACKEND" ]] && PY_BACKEND="MINICONDA"   # default if cancelled
USE_UV=false
[[ "$PY_BACKEND" == "UV" ]] && USE_UV=true

# -- Tools & extras -------------------------------------------------------------
# IS_INTERACTIVE pre-selects desktop defaults; all can be overridden below.
INSTALL_VSCODE=false
INSTALL_FONTS=false
INSTALL_KITTY=false
INSTALL_PODMAN=false
INSTALL_RUST=false
INSTALL_RUST_WASM=false
INSTALL_RUST_NIGHTLY=false
INSTALL_CROSS=false
INSTALL_TYPST=false
INSTALL_NODEJS=false

if $IS_INTERACTIVE; then
    INSTALL_VSCODE=true
    INSTALL_FONTS=true
    INSTALL_KITTY=true
fi

while true; do
    _vc=$( $INSTALL_VSCODE       && echo on || echo off)
    _fn=$( $INSTALL_FONTS        && echo on || echo off)
    _kt=$( $INSTALL_KITTY        && echo on || echo off)
    _p=$(  $INSTALL_PODMAN       && echo on || echo off)
    _r=$(  $INSTALL_RUST         && echo on || echo off)
    _rw=$( $INSTALL_RUST_WASM    && echo on || echo off)
    _rn=$( $INSTALL_RUST_NIGHTLY && echo on || echo off)
    _ty=$( $INSTALL_TYPST        && echo on || echo off)
    _cx=$( $INSTALL_CROSS        && echo on || echo off)
    _nj=$( $INSTALL_NODEJS       && echo on || echo off)

    dialog --backtitle "ubuntu-setup configurator" \
        --title " Tools & Extras " \
        --checklist \
"Select components to install.  Space = toggle,  Enter = confirm.\n\
  Rust sub-items (WASM/Nightly/Typst) automatically enable Rust.\n\
  Selecting Cross automatically enables Podman + Rust." \
        0 0 12 \
        "VSCODE"       "VS Code editor"                       "$_vc" \
        "FONTS"        "Nerd Fonts (CascadiaCode, Meslo)"     "$_fn" \
        "KITTY"        "Kitty terminal emulator"              "$_kt" \
        "PODMAN"       "Podman (container engine)"            "$_p"  \
        "RUST"         "Rust toolchain (rustup)"              "$_r"  \
        "RUST_WASM"    "  +- WASM target (wasm32-unknown)"   "$_rw" \
        "RUST_NIGHTLY" "  +- Nightly toolchain"              "$_rn" \
        "TYPST"        "  +- Typst document compiler"        "$_ty" \
        "CROSS"        "  +- Cross (needs Podman + Rust)"    "$_cx" \
        "NODEJS"       "Node.js LTS (via nvm)"               "$_nj" \
        2>"$TMP"

    # Cancelled -> keep current state and move on
    [[ $? -ne 0 ]] && break

    TOOLS=$(cat "$TMP")
    INSTALL_VSCODE=false;       selected VSCODE       "$TOOLS" && INSTALL_VSCODE=true
    INSTALL_FONTS=false;        selected FONTS        "$TOOLS" && INSTALL_FONTS=true
    INSTALL_KITTY=false;        selected KITTY        "$TOOLS" && INSTALL_KITTY=true
    INSTALL_PODMAN=false;       selected PODMAN       "$TOOLS" && INSTALL_PODMAN=true
    INSTALL_RUST=false;         selected RUST         "$TOOLS" && INSTALL_RUST=true
    INSTALL_RUST_WASM=false;    selected RUST_WASM    "$TOOLS" && INSTALL_RUST_WASM=true
    INSTALL_RUST_NIGHTLY=false; selected RUST_NIGHTLY "$TOOLS" && INSTALL_RUST_NIGHTLY=true
    INSTALL_TYPST=false;        selected TYPST        "$TOOLS" && INSTALL_TYPST=true
    INSTALL_CROSS=false;        selected CROSS        "$TOOLS" && INSTALL_CROSS=true
    INSTALL_NODEJS=false;       selected NODEJS       "$TOOLS" && INSTALL_NODEJS=true

    # Rust sub-items automatically pull in the Rust toolchain.
    if { $INSTALL_RUST_WASM || $INSTALL_RUST_NIGHTLY || $INSTALL_TYPST; } && ! $INSTALL_RUST; then
        INSTALL_RUST=true
    fi

    # Cross requires Podman + Rust - auto-enable both.
    if $INSTALL_CROSS; then
        INSTALL_PODMAN=true
        INSTALL_RUST=true
    fi

    break
done

# -- Build summary string -------------------------------------------------------
yn() { $1 && echo "yes" || echo "no"; }

cat > "$SUMMARY_FILE" <<SUMMARY
Hostname        : $SETUP_HOSTNAME
Interactive     : $(yn $IS_INTERACTIVE)
-----------------------------------------
Git name        : ${GIT_NAME:-(not set)}
Git email       : ${GIT_EMAIL:-(not set)}
-----------------------------------------
GPG import      : $(yn $GPG_IMPORT)$(  $GPG_IMPORT && echo " -> $(basename "$GPG_KEY_FILE")" || true)
$( $GPG_IMPORT && [[ -n "$GPG_FINGERPRINT" ]] && echo "GPG fingerprint : $GPG_FINGERPRINT" || true)
SSH import      : $(yn $SSH_COPY)$(     $SSH_COPY      && echo " -> $SSH_SRC_DIR" || true)
SSH generated   : $(yn $SSH_GENERATE)
Zsh as default  : $(yn $ZSH_AS_DEFAULT)
-----------------------------------------
Python backend  : $PY_BACKEND
-----------------------------------------
VS Code         : $(yn $INSTALL_VSCODE)
Nerd Fonts      : $(yn $INSTALL_FONTS)
Kitty terminal  : $(yn $INSTALL_KITTY)
Podman          : $(yn $INSTALL_PODMAN)
Rust            : $(yn $INSTALL_RUST)
  WASM target   : $(yn $INSTALL_RUST_WASM)
  Nightly       : $(yn $INSTALL_RUST_NIGHTLY)
  Cross         : $(yn $INSTALL_CROSS)
  Typst         : $(yn $INSTALL_TYPST)
Node.js         : $(yn $INSTALL_NODEJS)
-----------------------------------------
Output file     : $CONFIG_FILE
SUMMARY

# -- Confirm + write ------------------------------------------------------------
# Show summary in a scrollable textbox (auto-sizes to terminal, handles resize)
dialog --backtitle "ubuntu-setup configurator" \
    --title " Configuration Summary " \
    --textbox "$SUMMARY_FILE" 0 0

# Separate confirmation prompt
dialog --backtitle "ubuntu-setup configurator" \
    --title " Save Configuration " \
    --yesno "Save this configuration to:\n\n  $CONFIG_FILE" \
    9 66

if [[ $? -ne 0 ]]; then
    dialog --title " Cancelled " \
        --msgbox "Configuration was NOT saved." 6 42
    exit 0
fi

# Write a sourceable shell config file.
# GPG import, SSH copy, and SSH keygen were all performed live above by
# configure.sh - install.sh must not repeat them.  Only the fingerprint is
# kept so install.sh can wire up git commit signing.
# Use printf '%q' to safely quote string values.
Q_HOSTNAME=$(printf '%q' "$SETUP_HOSTNAME")
Q_GIT_NAME=$(printf '%q' "$GIT_NAME")
Q_GIT_EMAIL=$(printf '%q' "$GIT_EMAIL")
Q_GPG_FPR=$(printf '%q'  "$GPG_FINGERPRINT")

mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<CONF
# ubuntu-setup configuration
# Generated by configure.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Source this file in install.sh:  source "$CONFIG_FILE"
#
# NOTE: GPG import, SSH key copy, and SSH keygen were completed by
# configure.sh.  install.sh reads this file but does NOT redo those steps.

SETUP_HOSTNAME=$Q_HOSTNAME
IS_INTERACTIVE=$IS_INTERACTIVE

GIT_NAME=$Q_GIT_NAME
GIT_EMAIL=$Q_GIT_EMAIL

# Fingerprint of the already-imported GPG key; empty if none was imported.
# install.sh uses this to run: git config --global user.signingkey / commit.gpgsign
GPG_FINGERPRINT=$Q_GPG_FPR

ZSH_AS_DEFAULT=$ZSH_AS_DEFAULT

USE_UV=$USE_UV

INSTALL_VSCODE=$INSTALL_VSCODE
INSTALL_FONTS=$INSTALL_FONTS
INSTALL_KITTY=$INSTALL_KITTY
INSTALL_PODMAN=$INSTALL_PODMAN
INSTALL_RUST=$INSTALL_RUST
INSTALL_RUST_WASM=$INSTALL_RUST_WASM
INSTALL_RUST_NIGHTLY=$INSTALL_RUST_NIGHTLY
INSTALL_CROSS=$INSTALL_CROSS
INSTALL_TYPST=$INSTALL_TYPST
INSTALL_NODEJS=$INSTALL_NODEJS
CONF

chmod 600 "$CONFIG_FILE"   # paths/key locations are semi-sensitive

dialog --backtitle "ubuntu-setup configurator" \
    --title " Done " \
    --msgbox \
"Configuration saved to:\n\
\n\
  $CONFIG_FILE\n\
\n\
To run an unattended install:\n\
\n\
  bash bootstrap.sh --config $CONFIG_FILE" \
    13 62

clear
echo "Config written to: $CONFIG_FILE"
