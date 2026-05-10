#!/usr/bin/env bash
# install.sh — Fully unattended system installer driven by a config file
# produced by configure.sh.
#
# Usage:
#   bash install.sh --config ~/.setup.conf
#   bash install.sh              # uses ~/.setup.conf by default
#
# This script NEVER asks interactive questions.  All decisions come from the
# config file.  Run configure.sh first if you don't have one.

set -uo pipefail

# ── Require bash ───────────────────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Bash is required to run this script." >&2; exit 1
fi

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then tty_escape() { printf "\033[%sm" "$1"; }
else               tty_escape() { :; }; fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"; tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"; tty_reset="$(tty_escape 0)"

shell_join() {
    local arg; printf "%s" "$1"; shift
    for arg in "$@"; do printf " "; printf "%s" "${arg// /\ }"; done
}
chomp() { printf "%s" "${1/"$'\n'"/}"; }
ohai()  { printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"; }
info()  { printf "${tty_blue}INFO${tty_reset}: %s\n" "$(chomp "$1")" >&2; }
warn()  { printf "[${tty_red}WARN${tty_reset}] %s\n" "$(chomp "$1")" >&2; }
abort() { printf "%s\n" "$@" >&2; exit 1; }

# ── Sudo helpers ───────────────────────────────────────────────────────────────
unset HAVE_SUDO_ACCESS
have_sudo_access() {
    if [[ ! -x "/usr/bin/sudo" ]]; then return 1; fi
    local -a SUDO=("/usr/bin/sudo")
    [[ -n "${SUDO_ASKPASS-}" ]] && SUDO+=("-A")
    if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
        "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
        HAVE_SUDO_ACCESS="$?"
    fi
    [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]] && \
        abort "Need sudo access (user ${USER} must be an administrator)."
    return "${HAVE_SUDO_ACCESS}"
}
execute() { if ! "$@"; then abort "$(printf "Failed during: %s" "$(shell_join "$@")")"; fi; }
execute_sudo() {
    local -a args=("$@")
    if [[ "${EUID:-${UID}}" != "0" ]] && have_sudo_access; then
        [[ -n "${SUDO_ASKPASS-}" ]] && args=("-A" "${args[@]}")
        ohai "/usr/bin/sudo" "${args[@]}"
        execute "/usr/bin/sudo" "${args[@]}"
    fi
}

# ── Parse arguments ────────────────────────────────────────────────────────────
CONFIG_FILE="$HOME/.setup.conf"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#--config=}"; shift ;;
        *) abort "Unknown argument: $1" ;;
    esac
done

[[ -f "$CONFIG_FILE" ]] || abort "Config file not found: $CONFIG_FILE\nRun configure.sh first."

ohai "Loading config from $CONFIG_FILE"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ── Config defaults (in case of older/partial config files) ────────────────────
SETUP_HOSTNAME="${SETUP_HOSTNAME:-}"
IS_INTERACTIVE="${IS_INTERACTIVE:-false}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
GPG_FINGERPRINT="${GPG_FINGERPRINT:-}"
ZSH_AS_DEFAULT="${ZSH_AS_DEFAULT:-false}"
USE_UV="${USE_UV:-false}"
INSTALL_PODMAN="${INSTALL_PODMAN:-false}"
INSTALL_RUST="${INSTALL_RUST:-false}"
INSTALL_RUST_WASM="${INSTALL_RUST_WASM:-false}"
INSTALL_RUST_NIGHTLY="${INSTALL_RUST_NIGHTLY:-false}"
INSTALL_CROSS="${INSTALL_CROSS:-false}"
INSTALL_TYPST="${INSTALL_TYPST:-false}"
INSTALL_NODEJS="${INSTALL_NODEJS:-false}"

# ── Temp workspace ─────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
[[ -d "$WORK_DIR" ]] || abort "Could not create temp directory."
cleanup() { cd "$HOME" || true; rm -rf "$WORK_DIR"; }
trap cleanup EXIT
cd "$WORK_DIR"

# ── Platform detection ─────────────────────────────────────────────────────────
PLATFORM=$(uname -s)
ARCH=$(uname -m)

IS_MACOS=false; IS_DEBIAN=false; IS_ARCHLINUX=false; IS_FEDORA=false

MACOS()    { [[ "$IS_MACOS"     == true ]]; }
DEBIAN()   { [[ "$IS_DEBIAN"    == true ]]; }
ARCHLINUX(){ [[ "$IS_ARCHLINUX" == true ]]; }
FEDORA()   { [[ "$IS_FEDORA"    == true ]]; }
INTERACTIVE() { [[ "$IS_INTERACTIVE" == true ]]; }

if [[ "$PLATFORM" == "Linux" ]]; then
    ohai "Detected Linux"
    if [[ -f /etc/debian_version ]]; then
        IS_DEBIAN=true
        alias update-my-alternatives='update-alternatives --altdir ~/.local/etc/alternatives --admindir ~/.local/var/lib/alternatives'
        mkdir -p ~/.local/var/lib/alternatives ~/.local/etc/alternatives
        UPDATE="execute_sudo apt-get update -y"
        UPGRADE="execute_sudo apt-get upgrade -y"
        INSTALL="execute_sudo apt-get install -y"
        ADMIN=root
    elif [[ -f /etc/arch-release ]]; then
        IS_ARCHLINUX=true
        UPDATE="execute_sudo pacman -Sy --noconfirm"
        UPGRADE="execute_sudo pacman -Syu --noconfirm"
        INSTALL="execute_sudo pacman -S --noconfirm --needed"
        ADMIN=root
    elif [[ -f /etc/fedora-release ]]; then
        IS_FEDORA=true
        UPDATE="execute_sudo dnf makecache -y"
        UPGRADE="execute_sudo dnf upgrade -y"
        INSTALL="execute_sudo dnf install -y"
        ADMIN=root
    else
        abort "Unsupported Linux distribution."
    fi
elif [[ "$PLATFORM" == "Darwin" ]]; then
    ohai "Detected macOS"
    IS_MACOS=true
    if ! xcode-select -p &>/dev/null; then
        ohai "Installing Xcode command-line tools..."
        xcode-select --install
        until xcode-select --print-path &>/dev/null; do sleep 5; done
    fi
    SUDO_LOCAL=/etc/pam.d/sudo_local
    if [[ -f "$SUDO_LOCAL" ]] && ! grep -q "pam_tid" "$SUDO_LOCAL" 2>/dev/null; then
        ohai "Enabling Touch ID for sudo..."
        echo "auth       sufficient     pam_tid.so" | sudo tee -a "$SUDO_LOCAL" >/dev/null
    fi
    if ! command -v brew &>/dev/null; then
        ohai "Installing Homebrew..."
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
            --output "$WORK_DIR/brew_install.sh"
        bash "$WORK_DIR/brew_install.sh"
    fi
    if [[ "$ARCH" == "arm64" ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    else                              eval "$(/usr/local/bin/brew shellenv)"; fi
    UPDATE="brew update"
    UPGRADE="brew upgrade"
    INSTALL="brew install"
    ADMIN=admin
else
    abort "Unsupported platform: $PLATFORM"
fi

# ── Hostname ───────────────────────────────────────────────────────────────────
if [[ -n "$SETUP_HOSTNAME" && "$SETUP_HOSTNAME" != "$(hostname)" ]]; then
    ohai "Setting hostname to $SETUP_HOSTNAME"
    if MACOS; then
        sudo scutil --set HostName      "$SETUP_HOSTNAME"
        sudo scutil --set LocalHostName "$SETUP_HOSTNAME"
        sudo scutil --set ComputerName  "$SETUP_HOSTNAME"
    else
        execute_sudo hostnamectl set-hostname "$SETUP_HOSTNAME" 2>/dev/null || \
            echo "$SETUP_HOSTNAME" | execute_sudo tee /etc/hostname >/dev/null
    fi
fi

# ── Git configuration ──────────────────────────────────────────────────────────
# configure.sh sets these on the source machine; on a fresh install from a
# snapshot the git config is empty, so we re-apply from the config file.
ohai "Configuring git"
[[ -n "$GIT_NAME"  ]] && git config --global user.name  "$GIT_NAME"
[[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch master 2>/dev/null || true
if [[ -n "$GPG_FINGERPRINT" ]]; then
    git config --global user.signingkey "$GPG_FINGERPRINT"
    git config --global commit.gpgsign  true
    info "Git commit signing enabled with key $GPG_FINGERPRINT"
fi

# ── Package manager update / upgrade ──────────────────────────────────────────
ohai "Updating package manager"
$UPDATE  >/dev/null
$UPGRADE >/dev/null

# ── Essential build tools ─────────────────────────────────────────────────────
ohai "Installing essential build tools"
if MACOS; then
    $INSTALL wget gnupg pkg-config libusb gfortran pv >/dev/null
elif DEBIAN; then
    $INSTALL build-essential pkg-config libusb-1.0-0-dev libclang-dev \
             gfortran cifs-utils git git-lfs gnupg >/dev/null
elif ARCHLINUX; then
    $INSTALL base-devel pkgconf libusb clang gcc-fortran cifs-utils \
             wget python-pip git git-lfs gnupg >/dev/null
elif FEDORA; then
    $INSTALL gcc gcc-c++ make pkgconf-pkg-config libusbx-devel clang \
             gcc-gfortran cifs-utils wget python3-pip git git-lfs gnupg2 >/dev/null
fi

# ── rsync ─────────────────────────────────────────────────────────────────────
if ! MACOS && ! command -v rsync &>/dev/null; then
    info "Installing rsync..."
    $INSTALL rsync >/dev/null
fi

# ── zsh ───────────────────────────────────────────────────────────────────────
if ! MACOS && ! command -v zsh &>/dev/null; then
    ohai "Installing zsh"
    if DEBIAN; then execute_sudo apt-get install -y zsh >/dev/null
    else $INSTALL zsh >/dev/null; fi
fi
if [[ "$ZSH_AS_DEFAULT" == true ]] && [[ "$SHELL" != "$(command -v zsh)" ]]; then
    ohai "Setting zsh as default shell"
    chsh -s "$(command -v zsh)" "$USER"
fi

# ── Local bin path ─────────────────────────────────────────────────────────────
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# ── QoL CLI tools ─────────────────────────────────────────────────────────────
ohai "Installing QoL CLI tools"

command -v zoxide &>/dev/null || { info "zoxide..."; $INSTALL zoxide >/dev/null; }
command -v fzf    &>/dev/null || { info "fzf...";    $INSTALL fzf    >/dev/null; }
command -v tmux   &>/dev/null || { info "tmux...";   $INSTALL tmux   >/dev/null; }
command -v rg     &>/dev/null || { info "ripgrep..."; $INSTALL ripgrep >/dev/null; }
command -v jq     &>/dev/null || { info "jq...";     $INSTALL jq     >/dev/null; }
command -v btop   &>/dev/null || { info "btop...";   $INSTALL btop   >/dev/null; }

# eza / exa
if ! command -v eza &>/dev/null && ! command -v exa &>/dev/null; then
    info "eza..."
    $INSTALL eza >/dev/null || $INSTALL exa >/dev/null || warn "Could not install eza/exa."
fi

# bat (Debian has a name conflict → batcat)
if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
    info "bat..."
    $INSTALL bat >/dev/null || $INSTALL batcat >/dev/null || warn "Could not install bat."
    if DEBIAN && command -v batcat &>/dev/null; then
        ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
    fi
fi

# fd / fd-find
if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
    info "fd..."
    if DEBIAN; then
        $INSTALL fd-find >/dev/null && \
            ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
    elif FEDORA; then
        $INSTALL fd-find >/dev/null
    else
        $INSTALL fd >/dev/null
    fi
fi

# ── SSH / OpenSSL / unzip ──────────────────────────────────────────────────────
ohai "Installing SSH / OpenSSL / unzip"
if DEBIAN; then
    $INSTALL openssh-server openssh-client libssl-dev unzip >/dev/null
elif ARCHLINUX; then
    $INSTALL openssh openssl unzip >/dev/null
elif FEDORA; then
    $INSTALL openssh-server openssh-clients openssl-devel unzip >/dev/null
elif MACOS; then
    $INSTALL openssl nano >/dev/null
fi
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

# ── Fonts ──────────────────────────────────────────────────────────────────────
if INTERACTIVE; then
    ohai "Installing fonts"
    SYSTEM_FONT_DIR=""; FONT_TARGET_DIR=""; FONT_INSTALLED=false; FONTS_ALREADY_PRESENT=false
    if DEBIAN;    then SYSTEM_FONT_DIR="/usr/share/fonts/truetype"; fi
    if ARCHLINUX; then SYSTEM_FONT_DIR="/usr/share/fonts/TTF";      fi
    if FEDORA;    then SYSTEM_FONT_DIR="/usr/share/fonts/truetype"; fi

    if [[ -n "$SYSTEM_FONT_DIR" ]]; then
        execute_sudo mkdir -p "$SYSTEM_FONT_DIR"; FONT_TARGET_DIR="$SYSTEM_FONT_DIR"
    elif MACOS; then
        FONT_TARGET_DIR="$HOME/Library/Fonts"; mkdir -p "$FONT_TARGET_DIR"
    fi

    if [[ -n "$FONT_TARGET_DIR" ]]; then
        if compgen -G "$FONT_TARGET_DIR/*Caskaydia*Cove*NerdFont*.ttf" >/dev/null && \
           compgen -G "$FONT_TARGET_DIR/*Meslo*LGS*NerdFont*.ttf"      >/dev/null; then
            if DEBIAN; then
                compgen -G "$FONT_TARGET_DIR/*Aptos*.ttf" >/dev/null && FONTS_ALREADY_PRESENT=true
            else
                FONTS_ALREADY_PRESENT=true
            fi
        fi
    fi

    if $FONTS_ALREADY_PRESENT; then
        info "Required fonts already installed; skipping."
    else
        cd "$WORK_DIR"
        NERDFONT_VERSION=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
            | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
        info "Downloading CascadiaCode NerdFont v${NERDFONT_VERSION}..."
        curl -Lo CascadiaCode.tar.xz \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/CascadiaCode.tar.xz"
        tar xf CascadiaCode.tar.xz
        info "Downloading Meslo NerdFont..."
        curl -Lo Meslo.tar.xz \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/Meslo.tar.xz"
        tar xf Meslo.tar.xz
        if DEBIAN; then
            info "Downloading Microsoft Aptos fonts..."
            curl -Lo aptos.zip \
                "https://download.microsoft.com/download/8/6/0/860a94fa-7feb-44ef-ac79-c072d9113d69/Microsoft%20Aptos%20Fonts.zip"
            unzip -o aptos.zip -d aptos >/dev/null
        fi
        for font_file in "$WORK_DIR"/*.ttf; do
            [[ -f "$font_file" ]] || continue
            if DEBIAN || ARCHLINUX || FEDORA; then
                execute_sudo cp "$font_file" "$SYSTEM_FONT_DIR/"
                FONT_INSTALLED=true
            elif MACOS; then
                cp "$font_file" "$FONT_TARGET_DIR/"
                FONT_INSTALLED=true
            fi
        done
        if (DEBIAN || ARCHLINUX || FEDORA) && $FONT_INSTALLED; then
            info "Updating font cache..."
            execute_sudo fc-cache -f -v >/dev/null
        fi
        cd "$WORK_DIR"
    fi
fi

# ── starship ───────────────────────────────────────────────────────────────────
if ! command -v starship &>/dev/null; then
    ohai "Installing starship"
    curl -sSf https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
fi

# ── kitty terminal ─────────────────────────────────────────────────────────────
if INTERACTIVE; then
    if (DEBIAN || ARCHLINUX || FEDORA) && ! command -v kitty &>/dev/null; then
        ohai "Installing kitty"
        if ARCHLINUX || FEDORA; then
            $INSTALL kitty >/dev/null
        else
            curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
            ln -sf "$HOME/.local/kitty.app/bin/kitty" \
                   "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/"
            mkdir -p "$HOME/.local/share/applications"
            cp "$HOME/.local/kitty.app/share/applications/kitty.desktop" \
               "$HOME/.local/kitty.app/share/applications/kitty-open.desktop" \
               "$HOME/.local/share/applications/" 2>/dev/null || true
            sed -i "s|Icon=kitty|Icon=$(readlink -f ~)/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" \
                "$HOME/.local/share/applications/kitty"*.desktop
            sed -i "s|Exec=kitty|Exec=$(readlink -f ~)/.local/kitty.app/bin/kitty|g" \
                "$HOME/.local/share/applications/kitty"*.desktop
            echo 'kitty.desktop' > "$HOME/.config/xdg-terminals.list"
            update-my-alternatives --install "$HOME/.local/bin/x-terminal-emulator" \
                x-terminal-emulator "$HOME/.local/bin/kitty" 50 2>/dev/null || true
        fi
    elif MACOS && [[ ! -d "/Applications/kitty.app" ]]; then
        ohai "Installing kitty (macOS)"
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
    fi
fi

# ── Podman ─────────────────────────────────────────────────────────────────────
PODMAN_INSTALLED=false
if command -v podman &>/dev/null; then
    PODMAN_INSTALLED=true
elif [[ "$INSTALL_PODMAN" == true ]]; then
    ohai "Installing Podman"
    $INSTALL podman && PODMAN_INSTALLED=true || warn "Podman install failed."
fi

# ── Rust toolchain ─────────────────────────────────────────────────────────────
RUST_INSTALLED=false
if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    RUST_INSTALLED=true
elif [[ "$INSTALL_RUST" == true ]]; then
    ohai "Installing Rust toolchain"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    RUST_INSTALLED=true
fi

if $RUST_INSTALLED; then
    if [[ "$INSTALL_RUST_WASM" == true ]]; then
        ohai "Adding WASM target"
        rustup target add wasm32-unknown-unknown
    fi
    if [[ "$INSTALL_RUST_NIGHTLY" == true ]]; then
        ohai "Installing nightly toolchain"
        rustup toolchain install nightly
    fi
    cargo install cargo-cache    2>/dev/null || true
    cargo install cargo-clean-all 2>/dev/null || true
fi

# ── Cross ──────────────────────────────────────────────────────────────────────
if [[ "$INSTALL_CROSS" == true ]] && $RUST_INSTALLED && $PODMAN_INSTALLED; then
    if ! command -v cross &>/dev/null; then
        ohai "Installing cross"
        cargo install cross --git https://github.com/cross-rs/cross
    fi
fi

# ── lazygit ────────────────────────────────────────────────────────────────────
if ! command -v lazygit &>/dev/null; then
    ohai "Installing lazygit"
    if DEBIAN || FEDORA; then
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
            | grep -Po '"tag_name": *"v\K[^"]*')
        curl -Lo "$WORK_DIR/lazygit.tar.gz" \
            "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        tar xf "$WORK_DIR/lazygit.tar.gz" -C "$WORK_DIR" lazygit
        install "$WORK_DIR/lazygit" -D -t "$HOME/.local/bin/"
    elif ARCHLINUX; then $INSTALL lazygit >/dev/null
    elif MACOS;     then $INSTALL lazygit >/dev/null
    fi
fi

# ── Neovim ─────────────────────────────────────────────────────────────────────
if ! command -v nvim &>/dev/null; then
    ohai "Installing Neovim"
    if DEBIAN; then
        NEOVIM_VERSION=$(curl -s "https://api.github.com/repos/neovim/neovim/releases/latest" \
            | grep -Po '"tag_name": *"v\K[^"]*')
        curl -Lo "$WORK_DIR/neovim.tar.gz" \
            "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz"
        tar xf "$WORK_DIR/neovim.tar.gz" -C "$WORK_DIR"
        execute_sudo cp -r "$WORK_DIR/nvim-linux-x86_64/." /usr/local
    elif ARCHLINUX; then $INSTALL neovim >/dev/null
    elif FEDORA;    then $INSTALL neovim >/dev/null
    elif MACOS;     then $INSTALL neovim >/dev/null
    fi
fi

# ── termdown / countdown ───────────────────────────────────────────────────────
if ! command -v termdown &>/dev/null && ! command -v countdown &>/dev/null; then
    ohai "Installing termdown"
    if DEBIAN; then
        /usr/bin/python3 -m pip install --break-system-packages termdown
    elif ARCHLINUX || FEDORA; then
        /usr/bin/python3 -m pip install --user termdown
    elif MACOS; then
        $INSTALL countdown >/dev/null
    fi
fi

# ── Typst ──────────────────────────────────────────────────────────────────────
if [[ "$INSTALL_TYPST" == true ]]; then
    if ! command -v typst &>/dev/null; then
        if $RUST_INSTALLED; then
            ohai "Installing Typst"
            cargo install --locked typst-cli
            [[ -e "/usr/local/bin/typst" || -L "/usr/local/bin/typst" ]] && \
                execute_sudo rm -f /usr/local/bin/typst
            execute_sudo ln -s "$HOME/.cargo/bin/typst" /usr/local/bin/typst
        else
            warn "Typst requires Rust; skipping."
        fi
    fi
fi

# ── oh-my-zsh + plugins ────────────────────────────────────────────────────────
ohai "Installing oh-my-zsh and plugins"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
fi

_OMZ_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

[[ -d "$_OMZ_CUSTOM/themes/powerlevel10k" ]] || \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "$_OMZ_CUSTOM/themes/powerlevel10k" &>/dev/null || warn "powerlevel10k clone failed."

[[ -d "$_OMZ_CUSTOM/plugins/zsh-autosuggestions" ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        "$_OMZ_CUSTOM/plugins/zsh-autosuggestions" &>/dev/null || warn "zsh-autosuggestions clone failed."

[[ -d "$_OMZ_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
        "$_OMZ_CUSTOM/plugins/zsh-syntax-highlighting" &>/dev/null || warn "zsh-syntax-highlighting clone failed."

[[ -d "$_OMZ_CUSTOM/plugins/fzf-tab" ]] || \
    git clone https://github.com/Aloxaf/fzf-tab.git \
        "$_OMZ_CUSTOM/plugins/fzf-tab" &>/dev/null || warn "fzf-tab clone failed."

# ── tmux plugins ───────────────────────────────────────────────────────────────
ohai "Installing tmux plugins"
if [[ ! -d "$HOME/.config/tmux/plugins/catppuccin/tmux" ]]; then
    CATPPUCCIN_VERSION=$(curl -s "https://api.github.com/repos/catppuccin/tmux/releases/latest" \
        | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    mkdir -p "$HOME/.config/tmux/plugins/catppuccin"
    git clone -b "v${CATPPUCCIN_VERSION}" https://github.com/catppuccin/tmux.git \
        "$HOME/.config/tmux/plugins/catppuccin/tmux" &>/dev/null || warn "catppuccin/tmux clone failed."
fi

if [[ ! -d "$HOME/.tmux/plugins/tmuxifier" ]]; then
    mkdir -p "$HOME/.tmux/plugins"
    git clone https://github.com/jimeh/tmuxifier.git \
        "$HOME/.tmux/plugins/tmuxifier" &>/dev/null || warn "tmuxifier clone failed."
fi

if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    mkdir -p "$HOME/.tmux/plugins"
    git clone https://github.com/tmux-plugins/tpm.git \
        "$HOME/.tmux/plugins/tpm" &>/dev/null || warn "tpm clone failed."
fi

# ── zplug ──────────────────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.zplug" ]]; then
    ohai "Installing zplug"
    git clone https://github.com/zplug/zplug "$HOME/.zplug" &>/dev/null || warn "zplug clone failed."
fi

# ── Dotfiles ───────────────────────────────────────────────────────────────────
ohai "Installing dotfiles"
cd "$WORK_DIR"
# /releases/latest never returns pre-releases; use the releases list and
# pick the first entry (most recent, including pre-releases) when the
# UBUNTU_SETUP_PRERELEASE env var is set, otherwise use /releases/latest.
if [[ "${UBUNTU_SETUP_PRERELEASE:-}" == "1" ]]; then
    UBUNTU_SETUP_VERSION=$(curl -s "https://api.github.com/repos/sunipkm/ubuntu-setup/releases" \
        | grep tag_name | head -1 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+(-pre[0-9]+)?).*/\1/p')
else
    UBUNTU_SETUP_VERSION=$(curl -s "https://api.github.com/repos/sunipkm/ubuntu-setup/releases/latest" \
        | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
fi
if [[ -n "$UBUNTU_SETUP_VERSION" ]]; then
    curl -Lo dotfiles_installer.sh \
        "https://github.com/sunipkm/ubuntu-setup/releases/download/v${UBUNTU_SETUP_VERSION}/dotfiles_installer.sh"
    DOTFILES_VERSION=$(grep -m1 '^DOTFILES_VERSION=' dotfiles_installer.sh | cut -d'"' -f2)
    ohai "Installing dotfiles ${DOTFILES_VERSION:-v${UBUNTU_SETUP_VERSION}}"
    bash dotfiles_installer.sh || warn "dotfiles_installer.sh failed."
else
    warn "Could not determine ubuntu-setup release version; skipping dotfiles."
fi

# ── Install setup-snapshot ─────────────────────────────────────────────────────
ohai "Installing setup-snapshot"
SNAPSHOT_URL="https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/snapshot.sh"
mkdir -p "$HOME/.local/bin"
if curl -fsSL "$SNAPSHOT_URL" -o "$HOME/.local/bin/setup-snapshot"; then
    chmod 755 "$HOME/.local/bin/setup-snapshot"
    info "setup-snapshot installed to ~/.local/bin/setup-snapshot"
else
    warn "Could not download snapshot.sh; setup-snapshot will not be available."
fi

# ── Platform-specific .zshrc patches ──────────────────────────────────────────
ohai "Patching .zshrc for platform"
if DEBIAN || ARCHLINUX || FEDORA; then
    sed -i '/#LD_LIBRARY_PATH/c\export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib:$LD_LIBRARY_PATH' \
        "$HOME/.zshrc" 2>/dev/null || true
    if ARCHLINUX; then
        mkdir -p "$HOME/.config/Code - OSS/User"
        [[ -f "$HOME/.config/Code/User/settings.json" ]] && \
            cp "$HOME/.config/Code/User/settings.json" \
               "$HOME/.config/Code - OSS/User/settings.json"
    fi
elif MACOS; then
    mkdir -p "$HOME/Library/Application Support/Code/User"
    [[ -f "$HOME/.config/Code/User/settings.json" ]] && \
        cp "$HOME/.config/Code/User/settings.json" \
           "$HOME/Library/Application Support/Code/User/"
    sed -i '' "s/#LD_LIBRARY_PATH/export DYLD_LIBRARY_PATH=\/usr\/local\/lib:\/usr\/lib:\$DYLD_LIBRARY_PATH/g" \
        "$HOME/.zshrc" 2>/dev/null || true
    sed -i '' "s/termdown/countdown/g" "$HOME/.zshrc" 2>/dev/null || true
    if [[ "$ARCH" == "arm64" ]]; then
        sed -i '' 's/#HOMEBREW_IMPORT/eval "$(\/opt\/homebrew\/bin\/brew shellenv)"/g' \
            "$HOME/.zshrc" 2>/dev/null || true
    else
        sed -i '' 's/#HOMEBREW_IMPORT/eval "$(\/usr\/local\/bin\/brew shellenv)"/g' \
            "$HOME/.zshrc" 2>/dev/null || true
    fi
    sed -i '' 's/#HOMEBREW_COMPLETIONS/fpath=($fpath "$HOMEBREW_PREFIX\/share\/zsh\/site-functions")/g' \
        "$HOME/.zshrc" 2>/dev/null || true
    echo 'include $HOMEBREW_CELLAR/nano/*/share/nano/*.nanorc' >> "$HOME/.nanorc"
fi

# NVM init block
if ! grep -q "### NVM INIT ###" "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" <<'EOF'
### NVM INIT ###
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
### END NVM INIT ###
EOF
fi

# ── Python ─────────────────────────────────────────────────────────────────────
ohai "Installing Python"
if [[ "$USE_UV" == true ]]; then
    if ! command -v uv &>/dev/null; then
        info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    if ! UV_PYTHON=$(UV_PYTHON_INSTALL_DIR="$HOME/.uvpython3" uv python find 3.13 2>/dev/null); then
        uv python install 3.13 --install-dir "$HOME/.uvpython3" --default
        UV_PYTHON=$(UV_PYTHON_INSTALL_DIR="$HOME/.uvpython3" uv python find 3.13)
    fi
    export PATH="$(dirname "$UV_PYTHON"):$PATH"
    PIP_INSTALL="uv pip install --python $UV_PYTHON --system"
else
    if [[ ! -f "$HOME/.miniconda3/bin/activate" ]]; then
        if DEBIAN || ARCHLINUX || FEDORA; then MINICONDA_INSTALLER="Miniconda3-latest-Linux-${ARCH}.sh"
        elif MACOS;                         then MINICONDA_INSTALLER="Miniconda3-latest-MacOSX-${ARCH}.sh"
        fi
        curl -Lo "$WORK_DIR/$MINICONDA_INSTALLER" \
            "https://repo.anaconda.com/miniconda/$MINICONDA_INSTALLER"
        chmod +x "$WORK_DIR/$MINICONDA_INSTALLER"
        "$WORK_DIR/$MINICONDA_INSTALLER" -b -u -p "$HOME/.miniconda3"
        # shellcheck source=/dev/null
        source "$HOME/.miniconda3/bin/activate"
        conda config --set changeps1 false
    else
        # shellcheck source=/dev/null
        source "$HOME/.miniconda3/bin/activate"
    fi
    PIP_INSTALL="pip install"
fi

ohai "Installing Python packages"
$PIP_INSTALL numpy matplotlib xarray dask netcdf4 astropy scipy \
             scikit-image natsort fortls ipykernel jupyter
$PIP_INSTALL "skmpython@git+https://github.com/sunipkm/skmpython"

# ── VS Code ────────────────────────────────────────────────────────────────────
EXTENSIONS_URL="https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/extensions.txt"

if INTERACTIVE; then
    if ! command -v code &>/dev/null; then
        ohai "Installing VS Code"
        if DEBIAN; then
            execute_sudo apt-get install -y wget gpg >/dev/null
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
                | gpg --dearmor > "$WORK_DIR/packages.microsoft.gpg"
            execute_sudo install -D -o root -g root -m 644 \
                "$WORK_DIR/packages.microsoft.gpg" /etc/apt/keyrings/packages.microsoft.gpg
            execute_sudo sh -c \
                'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
            execute_sudo apt-get install -y apt-transport-https >/dev/null
            execute_sudo apt-get update >/dev/null
            execute_sudo apt-get install -y code >/dev/null
            execute_sudo apt-get -f install -y >/dev/null
        elif ARCHLINUX; then $INSTALL code >/dev/null
        elif FEDORA; then
            execute_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
                | execute_sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
            execute_sudo dnf check-update >/dev/null || true
            $INSTALL code >/dev/null || warn "VS Code install failed on Fedora."
        elif MACOS; then
            brew install --cask visual-studio-code >/dev/null
            ln -sf "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
                "$HOME/.local/bin/code"
        fi
    fi
    info "Installing VS Code extensions..."
    while read -r ext; do
        [[ -z "$ext" ]] && continue
        code --install-extension "$ext" >/dev/null || true
    done < <(curl -fsSL "$EXTENSIONS_URL")
fi

# ── Node.js ────────────────────────────────────────────────────────────────────
if [[ "$INSTALL_NODEJS" == true ]]; then
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        ohai "Installing nvm + Node.js LTS"
        NVM_VERSION=$(curl -s "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
            | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    fi
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    if command -v nvm &>/dev/null; then
        nvm install --lts
        nvm alias default 'lts/*'
    else
        warn "nvm unavailable after install; skipping Node.js LTS."
    fi
fi

export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

if command -v node &>/dev/null && command -v npm &>/dev/null; then
    if ! command -v yarn &>/dev/null; then
        ohai "Installing Yarn"
        npm install --global yarn >/dev/null || warn "Yarn install failed."
    fi
fi

# ── Microsoft fonts ────────────────────────────────────────────────────────────
if DEBIAN; then
    ohai "Installing Microsoft core fonts"
    execute_sudo apt-get install -y ttf-mscorefonts-installer
elif ARCHLINUX; then
    if ! command -v yay &>/dev/null && [[ "${EUID:-${UID}}" != "0" ]]; then
        ohai "Building yay (AUR helper)"
        YAY_BUILD_DIR="$WORK_DIR/yay-build"
        git clone https://aur.archlinux.org/yay-bin.git "$YAY_BUILD_DIR" &>/dev/null || \
            git clone https://aur.archlinux.org/yay.git  "$YAY_BUILD_DIR" &>/dev/null
        (cd "$YAY_BUILD_DIR" && makepkg -si --noconfirm >/dev/null) || warn "yay build failed."
    fi
    if command -v yay &>/dev/null; then
        yay -S --noconfirm --needed \
            ttf-ms-fonts ttf-vista-fonts ttf-office-2007-fonts \
            ttf-win7-fonts ttf-ms-win8 ttf-ms-win10 ttf-ms-win11 >/dev/null || \
            warn "One or more Microsoft font packages failed."
    fi
elif FEDORA; then
    warn "Microsoft core fonts not available by default on Fedora; skipping."
fi

# ── Cleanup ────────────────────────────────────────────────────────────────────
ohai "Cleaning up"
if DEBIAN; then
    execute_sudo apt-get autoremove -y >/dev/null
elif ARCHLINUX; then
    execute_sudo pacman -Sc --noconfirm >/dev/null
elif FEDORA; then
    execute_sudo dnf autoremove -y >/dev/null
    execute_sudo dnf clean all    >/dev/null
elif MACOS; then
    brew cleanup --prune all &>/dev/null
fi

ohai "Installation complete!"
printf "\nRestart your shell or run:  exec zsh\n\n"
