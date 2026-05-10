#!/usr/bin/env bash
# wsl_bootstrap.sh — Runs inside a freshly provisioned WSL distro.
#
# This script is written into the WSL home directory by wsl_resume.ps1 and
# run as the non-root user.  It:
#   1. Detects the distro family and installs prerequisites with the right
#      package manager (apt / pacman / dnf / zypper).
#   2. Verifies that ~/.setup.conf was written by wsl_resume.ps1.
#   3. Downloads the latest ubuntu-setup install.sh from GitHub.
#   4. Runs install.sh --config ~/.setup.conf to complete the Linux setup.
#
# The existing install.sh handles everything from here (dotfiles, oh-my-zsh,
# starship, Python, git, tmux plugins, VS Code server, etc.).

set -uo pipefail

# ── Require bash ───────────────────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Bash is required." >&2; exit 1
fi

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then tty_escape() { printf "\033[%sm" "$1"; }
else               tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"; tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"; tty_reset="$(tty_escape 0)"

ohai() { printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$*"; }
info() { printf "${tty_blue}INFO${tty_reset}: %s\n" "$1" >&2; }
warn() { printf "[${tty_red}WARN${tty_reset}] %s\n" "$1" >&2; }
abort(){ printf "%s\n" "$@" >&2; exit 1; }

# ── 1. Verify ~/.setup.conf ────────────────────────────────────────────────────
ohai "Checking ~/.setup.conf..."
[[ -f "$HOME/.setup.conf" ]] || abort \
    "~/.setup.conf not found.  wsl_resume.ps1 should have written this file.
Run install.ps1 again or create ~/.setup.conf manually."

info "Config:"
cat "$HOME/.setup.conf"
echo ""

# ── 2. Detect distro family and install prerequisites ────────────────────────
ohai "Detecting package manager..."

IS_DEBIAN=false; IS_ARCH=false; IS_FEDORA=false; IS_SUSE=false

if [[ -f /etc/debian_version ]]; then
    IS_DEBIAN=true
elif [[ -f /etc/arch-release ]]; then
    IS_ARCH=true
elif [[ -f /etc/fedora-release ]] || grep -q 'ID_LIKE=.*rhel' /etc/os-release 2>/dev/null; then
    IS_FEDORA=true
elif [[ -f /etc/SUSE-brand ]] || grep -q '^ID_LIKE=.*suse' /etc/os-release 2>/dev/null; then
    IS_SUSE=true
else
    warn "Could not identify distro; attempting apt-get as fallback."
    IS_DEBIAN=true
fi

if $IS_DEBIAN; then
    info "Package manager: apt-get"
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y  >/dev/null
    sudo apt-get upgrade -y >/dev/null
    sudo apt-get install -y curl git gnupg unzip >/dev/null
elif $IS_ARCH; then
    info "Package manager: pacman"
    sudo pacman -Syu --noconfirm >/dev/null
    sudo pacman -S --noconfirm --needed curl git gnupg unzip >/dev/null
elif $IS_FEDORA; then
    info "Package manager: dnf"
    sudo dnf makecache -y >/dev/null
    sudo dnf upgrade  -y >/dev/null
    sudo dnf install  -y curl git gnupg2 unzip >/dev/null
elif $IS_SUSE; then
    info "Package manager: zypper"
    sudo zypper refresh >/dev/null
    sudo zypper update  -y >/dev/null
    sudo zypper install -y curl git gpg2 unzip >/dev/null
fi

info "Prerequisites installed."

# ── 3. Locate or download install.sh ──────────────────────────────────────────
ohai "Fetching ubuntu-setup install.sh..."

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

# Query GitHub API for the latest release
RELEASE_TAG=$(curl -fsSL \
    "https://api.github.com/repos/sunipkm/ubuntu-setup/releases/latest" \
    | grep '"tag_name"' \
    | sed -nre 's/.*"tag_name":\s*"([^"]+)".*/\1/p')

if [[ -n "$RELEASE_TAG" ]]; then
    info "Latest ubuntu-setup release: $RELEASE_TAG"
    INSTALL_URL="https://github.com/sunipkm/ubuntu-setup/releases/download/${RELEASE_TAG}/install.sh"
    if curl -fsSLo install.sh "$INSTALL_URL" 2>/dev/null; then
        info "Downloaded install.sh from release $RELEASE_TAG."
    else
        warn "Release asset download failed; falling back to master branch."
        RELEASE_TAG=""
    fi
fi

if [[ -z "$RELEASE_TAG" ]]; then
    # Fall back to the master branch
    info "Downloading install.sh from master branch..."
    curl -fsSLo install.sh \
        "https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/install.sh"
fi

[[ -f install.sh ]] || abort "Failed to obtain install.sh."
chmod +x install.sh

# ── 4. Run the Linux installer ─────────────────────────────────────────────────
ohai "Running install.sh --config ~/.setup.conf ..."
echo ""
bash install.sh --config "$HOME/.setup.conf"

echo ""
ohai "Linux bootstrap complete!"
printf "Run 'exec zsh' or open a new terminal to start your configured shell.\n\n"
