#!/usr/bin/env bash
# setup.sh — Bootstraps the system just enough to run configure.sh, then
# launches it. This is the script users run first:
#
#   bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/setup.sh)"
#
# After configure.sh generates ~/.setup.conf, this script optionally launches
# install.sh to perform the full unattended installation.

set -u

# ── Require bash ───────────────────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Bash is required to run this script." >&2
    exit 1
fi

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    tty_escape() { printf "\033[%sm" "$1"; }
else
    tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
    local arg
    printf "%s" "$1"
    shift
    for arg in "$@"; do
        printf " "
        printf "%s" "${arg// /\ }"
    done
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

execute() {
    if ! "$@"; then
        abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
    fi
}

execute_sudo() {
    local -a args=("$@")
    if [[ "${EUID:-${UID}}" != "0" ]] && have_sudo_access; then
        [[ -n "${SUDO_ASKPASS-}" ]] && args=("-A" "${args[@]}")
        ohai "/usr/bin/sudo" "${args[@]}"
        execute "/usr/bin/sudo" "${args[@]}"
    fi
}

# ── Temp workspace ─────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
[[ -d "$WORK_DIR" ]] || abort "Could not create temp directory."

cleanup() {
    cd "$HOME" || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ── Platform detection ─────────────────────────────────────────────────────────
PLATFORM=$(uname -s)
ARCH=$(uname -m)

IS_MACOS=false
IS_DEBIAN=false
IS_ARCHLINUX=false
IS_FEDORA=false

MACOS()    { [[ "$IS_MACOS"     == true ]]; }
DEBIAN()   { [[ "$IS_DEBIAN"   == true ]]; }
ARCHLINUX(){ [[ "$IS_ARCHLINUX" == true ]]; }
FEDORA()   { [[ "$IS_FEDORA"   == true ]]; }

if [[ "$PLATFORM" == "Linux" ]]; then
    ohai "Detected Linux"
    if [[ -f /etc/debian_version ]]; then
        ohai "Debian-based system"
        IS_DEBIAN=true
        INSTALL="execute_sudo apt-get install -y"
        execute_sudo apt-get update -y
        ADMIN=root

    elif [[ -f /etc/arch-release ]]; then
        ohai "Arch Linux system"
        IS_ARCHLINUX=true
        INSTALL="execute_sudo pacman -S --noconfirm --needed"
        execute_sudo pacman -Sy --noconfirm
        ADMIN=root

    elif [[ -f /etc/fedora-release ]]; then
        ohai "Fedora system"
        IS_FEDORA=true
        INSTALL="execute_sudo dnf install -y"
        execute_sudo dnf makecache -y
        ADMIN=root

    else
        abort "Unsupported Linux distribution (Debian, Arch, and Fedora are supported)."
    fi

elif [[ "$PLATFORM" == "Darwin" ]]; then
    ohai "Detected macOS"
    IS_MACOS=true

    # Xcode command-line tools
    if ! xcode-select -p &>/dev/null; then
        ohai "Installing Xcode command-line tools..."
        xcode-select --install
        until xcode-select --print-path &>/dev/null; do sleep 5; done
    fi

    # Touch ID for sudo. A clean macOS ships only sudo_local.template, so create
    # the file when missing; skip if an active (uncommented) pam_tid line exists.
    SUDO_LOCAL=/etc/pam.d/sudo_local
    if ! grep -qs '^auth.*pam_tid\.so' "$SUDO_LOCAL"; then
        ohai "Enabling Touch ID for sudo..."
        echo "auth       sufficient     pam_tid.so" | sudo tee -a "$SUDO_LOCAL" >/dev/null
    fi

    # Homebrew: never stop to ask. Ask mode is the default since Homebrew 5
    # (prompts whenever an install pulls in dependencies); NONINTERACTIVE skips
    # the installer's "Press RETURN" prompt (it needs cached sudo credentials).
    export HOMEBREW_NO_ASK=1 HOMEBREW_NO_ENV_HINTS=1 NONINTERACTIVE=1
    if ! command -v brew &>/dev/null; then
        ohai "Installing Homebrew..."
        /usr/bin/sudo -v || abort "Need sudo access to install Homebrew."
        cd "$WORK_DIR"
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
            --output brew_install.sh
        bash brew_install.sh
        cd "$HOME"
    fi

    # Ensure brew is on PATH for the rest of this session
    if [[ "$ARCH" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    else
        eval "$(/usr/local/bin/brew shellenv)"    2>/dev/null || true
    fi

    INSTALL="brew install"
    ADMIN=admin

else
    abort "Unsupported platform: $PLATFORM"
fi

# ── Minimal prerequisites ──────────────────────────────────────────────────────
ohai "Installing minimal prerequisites..."

if DEBIAN; then
    $INSTALL git git-lfs gnupg dialog curl
elif ARCHLINUX; then
    $INSTALL git git-lfs gnupg dialog curl
elif FEDORA; then
    $INSTALL git git-lfs gnupg2 dialog curl
elif MACOS; then
    # git ships with Xcode tools; brew dialog is the TUI toolkit.
    # macOS has no gpg: configure.sh needs gnupg + pinentry-mac to import a key.
    $INSTALL dialog gnupg pinentry-mac
fi

# ── gpg-agent pinentry ─────────────────────────────────────────────────────────
# configure.sh imports the GPG secret key; gpg-agent needs a pinentry it can
# actually show (a GUI one on macOS, since dialog owns the terminal) to ask
# for the key's passphrase.
mkdir -p "$HOME/.gnupg" && chmod 700 "$HOME/.gnupg"
if MACOS; then
    PINENTRY_BIN="$(brew --prefix)/bin/pinentry-mac"
else
    PINENTRY_BIN="$(command -v pinentry-curses || command -v pinentry || true)"
fi
if [[ -n "$PINENTRY_BIN" && -x "$PINENTRY_BIN" ]]; then
    GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
    touch "$GPG_AGENT_CONF"
    if grep -q '^pinentry-program' "$GPG_AGENT_CONF"; then
        sed -i.bak "s|^pinentry-program.*|pinentry-program $PINENTRY_BIN|" "$GPG_AGENT_CONF" \
            && rm -f "$GPG_AGENT_CONF.bak"
    else
        echo "pinentry-program $PINENTRY_BIN" >> "$GPG_AGENT_CONF"
    fi
    gpgconf --kill gpg-agent &>/dev/null || true
fi

# ── Locate or download configure.sh ───────────────────────────────────────────
# If setup.sh is run from a local clone, use the sibling configure.sh.
# Otherwise download it from the repository.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CONFIGURE_SH=""

if [[ -f "$SCRIPT_DIR/configure.sh" ]]; then
    CONFIGURE_SH="$SCRIPT_DIR/configure.sh"
    info "Using local configure.sh from $SCRIPT_DIR"
else
    ohai "Downloading configure.sh..."
    CONFIGURE_SH="$WORK_DIR/configure.sh"
    curl -fsSL \
        "https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/configure.sh" \
        --output "$CONFIGURE_SH"
    chmod +x "$CONFIGURE_SH"
fi

# ── Locate or download install.sh (executor) ───────────────────────────────────
INSTALL_SH=""
if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
    INSTALL_SH="$SCRIPT_DIR/install.sh"
    info "Found local install.sh at $SCRIPT_DIR"
else
    INSTALL_SH_REMOTE="https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/install.sh"
    INSTALL_SH="$WORK_DIR/install.sh"
    curl -fsSL "$INSTALL_SH_REMOTE" --output "$INSTALL_SH" 2>/dev/null && \
        chmod +x "$INSTALL_SH" || \
        INSTALL_SH=""   # not fatal; can run manually later
fi

# ── Run the TUI configurator ───────────────────────────────────────────────────
CONFIG_FILE="$HOME/.setup.conf"

ohai "Launching configuration wizard..."
bash "$CONFIGURE_SH" "$CONFIG_FILE"
CONFIGURE_EXIT=$?

if [[ $CONFIGURE_EXIT -ne 0 ]]; then
    warn "configure.sh exited with code $CONFIGURE_EXIT. Setup aborted."
    exit "$CONFIGURE_EXIT"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "No config file was generated. Run configure.sh manually and then:"
    warn "  bash install.sh --config $CONFIG_FILE"
    exit 0
fi

# ── Offer to run the full install immediately ──────────────────────────────────
printf "\n"
ohai "Configuration saved to $CONFIG_FILE"

if [[ -n "$INSTALL_SH" ]]; then
    printf "${tty_bold}Run the full installation now?${tty_reset} [Y/n] "
    read -r response
    case "$response" in
        [nN][oO]|[nN])
            printf "\nTo run later, see the instructions at the top of %s\n\n" "$CONFIG_FILE"
            ;;
        *)
            ohai "Launching install.sh..."
            exec bash "$INSTALL_SH" --config "$CONFIG_FILE"
            ;;
    esac
else
    printf "To run the installation:\n"
    printf "  bash install.sh --config %s\n\n" "$CONFIG_FILE"
fi
