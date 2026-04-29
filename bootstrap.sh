#!/bin/bash
set -u

abort() {
    printf "%s\n" "$@" >&2
    exit 1
}

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
    abort "Bash is required to interpret this script."
fi

# string formatters
if [[ -t 1 ]]; then
    tty_escape() { printf "\033[%sm" "$1"; }
else
    tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
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

chomp() {
    printf "%s" "${1/"$'\n'"/}"
}

ohai() {
    printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

info() {
    printf "${tty_blue}INFO${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

warn() {
    printf "[${tty_red}WARN${tty_reset}] %s\n" "$(chomp "$1")" >&2
}

unset HAVE_SUDO_ACCESS # unset this from the environment

have_sudo_access() {
    if [[ ! -x "/usr/bin/sudo" ]]; then
        return 1
    fi
    
    local -a SUDO=("/usr/bin/sudo")
    if [[ -n "${SUDO_ASKPASS-}" ]]; then
        SUDO+=("-A")
    fi
    
    if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
        "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
        HAVE_SUDO_ACCESS="$?"
    fi
    
    if [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]]; then
        abort "Need sudo access on (e.g. the user ${USER} needs to be an Administrator)!"
    fi
    
    return "${HAVE_SUDO_ACCESS}"
}

execute() {
    if ! "$@"; then
        abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
    fi
}

execute_sudo() {
    local -a args=("$@")
    echo "Executing: ${args[*]}"
    if [[ "${EUID:-${UID}}" != "0" ]] && have_sudo_access; then
        if [[ -n "${SUDO_ASKPASS-}" ]]; then
            args=("-A" "${args[@]}")
        fi
        echo "Running with sudo: ${args[*]}"
        ohai "/usr/bin/sudo" "${args[@]}"
        execute "/usr/bin/sudo" "${args[@]}"
    else
        echo "Running as root, no need for sudo."
        # ohai "${args[@]}"
        # execute "${args[@]}"
    fi
}

confirm() {
    # call with a prompt string or use a default
    read -r -p "${tty_bold}${1:-Are you sure}?${tty_reset} [y/N] " response
    case "$response" in
        [yY][eE][sS] | [yY])
            true
        ;;
        *)
            false
        ;;
    esac
}

# the temp directory used, within $DIR
# omit the -p parameter to create a temporal directory in the default location
WORK_DIR=$(mktemp -d)

# check if tmp dir was created
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    echo "Could not create temp dir"
    exit 1
fi

# deletes the temp directory
function cleanup {
    cd "$HOME" || exit 1
    echo "Cleaning up temporary files..."
    rm -rf "$WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

cd $WORK_DIR

SPWD=$(pwd)
USER=$(whoami)

IS_MACOS=false
IS_DEBIAN=false
IS_ARCHLINUX=false
IS_FEDORA=false
IS_INTERACTIVE=false
IS_WSL=false

if [[ "$(< /proc/version)" == *@(Microsoft|WSL)* ]]; then
    IS_WSL=true
else
    IS_WSL=false
fi

function MACOS() {
    if [[ "$IS_MACOS" == true ]]; then
        return 0
    else
        return 1
    fi
}

function DEBIAN() {
    if [[ "$IS_DEBIAN" == true ]]; then
        return 0
    else
        return 1
    fi
}

function ARCHLINUX() {
    if [[ "$IS_ARCHLINUX" == true ]]; then
        return 0
    else
        return 1
    fi
}

function FEDORA() {
    if [[ "$IS_FEDORA" == true ]]; then
        return 0
    else
        return 1
    fi
}

function WSL() {
    if [[ "$IS_WSL" == true ]]; then
        return 0
    else
        return 1
    fi
}

function INTERACTIVE() {
    if [[ "$IS_INTERACTIVE" == true ]]; then
        return 0
    else
        return 1
    fi
}

PLATFORM=$(uname -s)
ARCH=$(uname -m)
if [[ "$PLATFORM" == "Linux" ]]; then
    echo "Detected Linux platform"
    if [[ -f /etc/debian_version ]]; then
        echo "Detected Debian-based system"
        alias update-my-alternatives='update-alternatives --altdir ~/.local/etc/alternatives --admindir ~/.local/var/lib/alternatives'
        mkdir -p ~/.local/var/lib/alternatives ~/.local/etc/alternatives
        IS_DEBIAN=true
        UPDATE="execute_sudo apt-get update -y"
        UPGRADE="execute_sudo apt-get upgrade -y"
        INSTALL="execute_sudo apt-get install -y"
        $UPDATE
        $UPGRADE
        $INSTALL git git-lfs -y &>/dev/null
        ADMIN=root
    elif [[ -f /etc/arch-release ]]; then
        echo "Detected Arch Linux system"
        IS_ARCHLINUX=true
        UPDATE="execute_sudo pacman -Sy --noconfirm"
        UPGRADE="execute_sudo pacman -Syu --noconfirm"
        INSTALL="execute_sudo pacman -S --noconfirm --needed"
        $UPDATE
        $UPGRADE
        $INSTALL git git-lfs >/dev/null
        ADMIN=root
    elif [[ -f /etc/fedora-release ]]; then
        echo "Detected Fedora system"
        IS_FEDORA=true
        UPDATE="execute_sudo dnf makecache -y"
        UPGRADE="execute_sudo dnf upgrade -y"
        INSTALL="execute_sudo dnf install -y"
        $UPDATE
        $UPGRADE
        $INSTALL git git-lfs >/dev/null
        ADMIN=root
    else
        abort "This script is intended for Debian-based, Arch Linux, or Fedora systems only."
    fi
elif [[ "$PLATFORM" == "Darwin" ]]; then
    echo "Detected macOS platform"
    IS_MACOS=true
    # Install xcode-select command line tools if not already installed
    if ! xcode-select -p &>/dev/null; then
        echo "Installing Xcode command line tools..."
        xcode-select --install
        # Wait for the installation to complete
        until $(xcode-select --print-path &>/dev/null); do
            sleep 5
        done
    fi
    ohai "Enabling touch ID for sudo..."
    echo "auth       sufficient     pam_tid.so" | sudo tee -a /etc/pam.d/sudo_local
    # Install Homebrew if not already installed
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh --output install.sh
        source ./install.sh
    fi
    UPDATE="brew update"
    UPGRADE="brew upgrade"
    INSTALL="brew install"
    ADMIN=admin
else
    abort "This script is intended for Debian Linux, Arch Linux, Fedora, and macOS platforms only."
fi

echo ""
echo ""

# Get git email
if [[ $(git config --global user.email) ]]; then
    info "Git email already set: $(git config --global user.email)"
else
    read -p "${tty_bold}Enter your git email: ${tty_reset}" GITEMAIL
    git config --global user.email "$GITEMAIL"
fi
# Get git username
if [[ $(git config --global user.name) ]]; then
    info "Git username already set: $(git config --global user.name)"
else
    read -p "${tty_bold}Enter your git full name: ${tty_reset}" GITUSER
    git config --global user.name "$GITUSER"
fi

# Set git branch name to master
git config --global init.defaultBranch master &>/dev/null

# Homebrew path
if MACOS; then
    if [[ "$ARCH" == "arm64" ]]; then
        echo "Detected ARM64 architecture"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo "Detected x86_64 architecture"
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi
info "Package manager update..."
$UPDATE >/dev/null
info "Package manager upgrade..."
$UPGRADE >/dev/null
info "Some essential packages..."

if MACOS; then
    $INSTALL wget >/dev/null
    $INSTALL pkg-config libusb gfortran pv
elif DEBIAN; then
    $INSTALL build-essential pkg-config libusb-1.0-0-dev libclang-dev gfortran cifs-utils >/dev/null
elif ARCHLINUX; then
    $INSTALL base-devel pkgconf libusb clang gcc-fortran cifs-utils wget python-pip >/dev/null
elif FEDORA; then
    $INSTALL gcc gcc-c++ make pkgconf-pkg-config libusbx-devel clang gcc-gfortran cifs-utils wget python3-pip >/dev/null
fi

if DEBIAN || ARCHLINUX || FEDORA; then
    if ! which rsync &>/dev/null; then
        info "Installing rsync..."
        $INSTALL rsync >/dev/null
    fi
    if ! which zsh &>/dev/null; then
        info "zsh not found, installing zsh..."
        if DEBIAN; then
            execute_sudo apt-get install zsh -y >/dev/null
        else
            $INSTALL zsh >/dev/null
        fi
        ohai "Enable zsh as default shell?"
        if confirm; then
            chsh -s "$(which zsh)" "$USER"
            info "zsh has been set as the default shell for $USER."
        else
            info "zsh has not been set as the default shell for $USER."
            info "You can set it later by running 'chsh -s \$(which zsh)'."
        fi
    fi
fi

info "Create local install path..."
mkdir -p ~/.local/bin >/dev/null
info "Set path to include local dir..."
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH" >/dev/null

confirm "Is this an interactive system" && IS_INTERACTIVE=true

if DEBIAN || ARCHLINUX || FEDORA ; then
    if INTERACTIVE; then
        if ! which kitty &>/dev/null && ! WSL; then
            if ARCHLINUX || FEDORA; then
                $INSTALL kitty >/dev/null
            else
                curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
                # Create symbolic links to add kitty and kitten to PATH (assuming ~/.local/bin is in
                # your system-wide PATH)
                ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/
                # Place the kitty.desktop file somewhere it can be found by the OS
                cp ~/.local/kitty.app/share/applications/kitty.desktop ~/.local/share/applications/
                # If you want to open text files and images in kitty via your file manager also add the kitty-open.desktop file
                cp ~/.local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
                # Update the paths to the kitty and its icon in the kitty desktop file(s)
                sed -i "s|Icon=kitty|Icon=$(readlink -f ~)/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" ~/.local/share/applications/kitty*.desktop
                sed -i "s|Exec=kitty|Exec=$(readlink -f ~)/.local/kitty.app/bin/kitty|g" ~/.local/share/applications/kitty*.desktop
                # Make xdg-terminal-exec (and hence desktop environments that support it use kitty)
                echo 'kitty.desktop' >~/.config/xdg-terminals.list
                echo "Setting kitty as default terminal..."
                update-my-alternatives --install ~/.local/bin/x-terminal-emulator x-terminal-emulator ~/.local/bin/kitty 50
                # Set as default terminal in gnome settings if gsettings is available
                if ! which gsettings &>/dev/null; then
                    gsettings set org.gnome.desktop.default-applications.terminal exec "$(readlink -f ~)/.local/bin/kitty"
                fi
            fi
        fi
    fi
elif MACOS; then
    if INTERACTIVE && [ ! -f "/Applications/kitty.app" ]; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
    fi
fi

info "Some QoL dependencies..."
if ! which zoxide &>/dev/null; then
    $INSTALL zoxide >/dev/null
else
    info "zoxide is already installed"
fi
if ! which fzf &>/dev/null; then
    $INSTALL fzf >/dev/null
else
    info "fzf is already installed"
fi

if (! which eza &>/dev/null) && (! which exa &>/dev/null); then
    $INSTALL eza >/dev/null
    if [ $? -ne 0 ]; then
        warn "Failed to install eza, trying exa..."
        $INSTALL exa >/dev/null
    fi
else
    info "eza or exa is already installed"
fi

if ! which batcat &>/dev/null; then
    $INSTALL bat >/dev/null
    if [ $? -ne 0 ]; then
        warn "Failed to install bat, trying batcat..."
        $INSTALL batcat >/dev/null
    fi
    if DEBIAN; then
        # bat name conflict
        mkdir -p ~/.local/bin >/dev/null
        ln -s /usr/bin/batcat ~/.local/bin/bat &>/dev/null
    fi
else
    info "bat is already installed"
fi
if ! which tmux &>/dev/null; then
    $INSTALL tmux >/dev/null
else
    info "tmux is already installed"
fi
if ! which ripgrep &>/dev/null; then
    $INSTALL ripgrep >/dev/null
else
    info "ripgrep is already installed"
fi
if ! which jq &>/dev/null; then
    $INSTALL jq >/dev/null
else
    info "jq is already installed"
fi
if ! which btop &>/dev/null; then
    $INSTALL btop >/dev/null
else
    info "btop is already installed"
fi

if DEBIAN; then
    if ! which fd-find &>/dev/null; then
        $INSTALL fd-find >/dev/null
        # Create a symlink to fd as fd-find
        mkdir -p ~/.local/bin >/dev/null
        ln -s /usr/bin/fdfind ~/.local/bin/fd &>/dev/null
    else
        info "fd-find is already installed"
    fi
elif MACOS; then
    if ! which fd &>/dev/null; then
        $INSTALL fd >/dev/null
    else
        info "fd is already installed"
    fi
elif ARCHLINUX; then
    if ! which fd &>/dev/null; then
        $INSTALL fd >/dev/null
    else
        info "fd is already installed"
    fi
elif FEDORA; then
    if ! which fd &>/dev/null; then
        $INSTALL fd-find >/dev/null
    else
        info "fd is already installed"
    fi
fi

if DEBIAN; then
    $INSTALL openssh-server openssh-client >/dev/null
    $INSTALL libssl-dev >/dev/null
    $INSTALL unzip >/dev/null
elif ARCHLINUX; then
    $INSTALL openssh openssl unzip >/dev/null
elif FEDORA; then
    $INSTALL openssh-server openssh-clients openssl-devel unzip >/dev/null
elif MACOS; then
    $INSTALL openssl >/dev/null
    $INSTALL nano >/dev/null
fi

# Generate ssh key
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    info "Generating ssh key with the ed25519 algorithm..."
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
fi

# Fonts
if INTERACTIVE || WSL; then
    cd $WORK_DIR
    info "Installing fonts..."
    SYSTEM_FONT_DIR=""
    if DEBIAN; then
        SYSTEM_FONT_DIR="/usr/share/fonts/truetype"
    elif ARCHLINUX; then
        SYSTEM_FONT_DIR="/usr/share/fonts/TTF"
    elif FEDORA; then
        SYSTEM_FONT_DIR="/usr/share/fonts/truetype"
    fi

    if [[ -n "$SYSTEM_FONT_DIR" ]] && ! WSL; then
        sudo mkdir -p "$SYSTEM_FONT_DIR"
    fi

    NERDFONT_VERSION=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    echo "Installing nerd fonts..."
    rm -vf *.ttf # delete all font files in there
    echo "Downloading Cascadia Code..."
    curl -Lo CascadiaCode.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/CascadiaCode.tar.xz"
    tar xf CascadiaCode.tar.xz
    echo "Downloading Meslo..."
    curl -Lo Meslo.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/Meslo.tar.xz"
    tar xf Meslo.tar.xz
    if DEBIAN; then
        curl -Lo "aptos.zip" "https://download.microsoft.com/download/8/6/0/860a94fa-7feb-44ef-ac79-c072d9113d69/Microsoft%20Aptos%20Fonts.zip"
        unzip -o aptos.zip -d aptos >/dev/null
    fi
    for font_file in $WORK_DIR/*.ttf; do
        if WSL; then
            if command -v powershell.exe &>/dev/null; then
                font_base=$(basename "$font_file")
                win_font_file=$(wslpath -w "$font_file")
                powershell.exe -NoProfile -Command "[void](New-Item -ItemType Directory -Force -Path (Join-Path \$env:LOCALAPPDATA 'Microsoft\\Windows\\Fonts')); Copy-Item -LiteralPath '$win_font_file' -Destination (Join-Path \$env:LOCALAPPDATA 'Microsoft\\Windows\\Fonts\\$font_base') -Force" >/dev/null
                powershell.exe -NoProfile -Command "New-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts' -Name '$font_base (TrueType)' -Value (Join-Path \$env:LOCALAPPDATA 'Microsoft\\Windows\\Fonts\\$font_base') -PropertyType String -Force | Out-Null" >/dev/null
            else
                warn "powershell.exe not found, skipping Windows font install from WSL."
                break
            fi
        elif DEBIAN || ARCHLINUX || FEDORA; then
            sudo cp "$font_file" "$SYSTEM_FONT_DIR/"
        elif MACOS; then
            cp "$font_file" $HOME/Library/Fonts/
        fi
    done

    if (DEBIAN || ARCHLINUX || FEDORA) && ! WSL; then
        info "Updating font cache..."
        sudo fc-cache -f -v >/dev/null
    fi
fi

if ! which starship &>/dev/null; then
    info "Installing starship..."
    curl -sSf https://starship.rs/install.sh | sh -s -- -y -b $HOME/.local/bin
fi

PODMAN_INSTALLED=false
if ! which podman &>/dev/null; then
    if confirm "Install podman"; then
        if (DEBIAN || ARCHLINUX || FEDORA) && ! WSL; then
            $INSTALL podman
            PODMAN_INSTALLED=true
        elif MACOS; then
            $INSTALL podman
            PODMAN_INSTALLED=true
        fi
    fi
else
    info "Podman is already installed"
    PODMAN_INSTALLED=true
fi

if ! [ -f "$HOME/.cargo/env" ]; then
    if confirm "Install Rust toolchain"; then
        info "Installing rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        . "$HOME/.cargo/env" # source cargo
        RUST_INSTALLED=true
    else
        warn "Rust toolchain not installed, some features may not work."
    fi
else
    . "$HOME/.cargo/env" # source cargo
    RUST_INSTALLED=true
fi

if $RUST_INSTALLED; then
    confirm "Install WASM toolchain" && rustup target add wasm32-unknown-unknown
    confirm "Install nightly toolchain" && rustup toolchain install nightly
    cargo install cargo-cache
    cargo install cargo-clean-all
fi

if $RUST_INSTALLED && $PODMAN_INSTALLED; then
    if ! which cross &>/dev/null; then
        if confirm "Install cross (cross-compilation tool)"; then
            info "Installing cross..."
            # Install cross using cargo
            if ! which cross &>/dev/null; then
                cargo install cross --git https://github.com/cross-rs/cross
            fi
        fi
    fi
fi

if ! which lazygit &>/dev/null; then
    info "Installing lazygit..."
    if DEBIAN; then
        # Lazygit
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
        curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        tar xf lazygit.tar.gz lazygit
        install lazygit -D -t $HOME/.local/bin/
    elif ARCHLINUX; then
        $INSTALL lazygit >/dev/null
    elif FEDORA; then
        $INSTALL lazygit >/dev/null
    elif MACOS; then
        $INSTALL lazygit >/dev/null
    fi
fi

if ! which nvim &>/dev/null; then
    info "Installing neovim..."
    if DEBIAN; then
        NEOVIM_VERSION=$(curl -s "https://api.github.com/repos/neovim/neovim/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
        curl -Lo neovim.tar.gz "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz"
        tar xf neovim.tar.gz
        execute_sudo "cp" "-r" "nvim-linux-x86_64/." "/usr/local"
    elif ARCHLINUX; then
        $INSTALL neovim >/dev/null
    elif FEDORA; then
        $INSTALL neovim >/dev/null
    elif MACOS; then
        $INSTALL neovim >/dev/null
    fi
fi

# termdown
if ! which termdown &>/dev/null; then
    info "Installing termdown..."
    if DEBIAN; then
        /usr/bin/python3 -m pip install --break-system-packages termdown
    elif ARCHLINUX; then
        /usr/bin/python3 -m pip install --user termdown
    elif FEDORA; then
        /usr/bin/python3 -m pip install --user termdown
    elif MACOS; then
        $INSTALL countdown >/dev/null
    fi
fi

if ! which typst &>/dev/null; then
    if [ "$RUST_INSTALLED" = true ]; then
        confirm "Install Typst" && cargo install --locked typst-cli
        execute_sudo ln -s "$HOME/.cargo/bin/typst" /usr/local/bin/
    else
        warn "Typst requires Rust, install the Rust toolchain, then run 'cargo install --locked typst-cli' to install Typst."
    fi
fi

# Install oh-my-zsh
if ! [ -d "$HOME/.oh-my-zsh" ]; then
    info "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install powerlevel10k
info "Installing powerlevel10k theme for oh-my-zsh..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" &>/dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone powerlevel10k."
fi

info "Installing zsh autosuggestions..."
git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions &>/dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone zsh-autosuggestions."
fi

info "Installing zsh syntax highlighting..."
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &>/dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone zsh-syntax-highlighting."
fi

info "Installing fzf-tab for zsh..."
git clone https://github.com/Aloxaf/fzf-tab.git $HOME/.oh-my-zsh/custom/plugins/fzf-tab &>/dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone fzf-tab."
fi

# Install catppuccin for tmux
if ! [ -d "$HOME/.config/tmux/catppuccin" ]; then
    info "Installing catppuccin for tmux..."
    CATPPUCCIN_VERSION=$(curl -s "https://api.github.com/repos/catppuccin/tmux/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    mkdir -p $HOME/.config/tmux/plugins/catppuccin
    git clone -b v$CATPPUCCIN_VERSION https://github.com/catppuccin/tmux.git $HOME/.config/tmux/plugins/catppuccin/tmux
fi

if ! [ -d "$HOME/.tmux/plugins/tmuxifier" ]; then
    info "Installing tmuxifier..."
    mkdir -p $HOME/.tmux/plugins
    git clone https://github.com/jimeh/tmuxifier.git $HOME/.tmux/plugins/tmuxifier
    if [ $? -ne 0 ]; then
        warn "Failed to clone tmuxifier."
    fi
fi

if ! [ -d "$HOME/.tmux/plugins/tpm" ]; then
    info "Installing tmux plugin manager..."
    mkdir -p $HOME/.tmux/plugins
    git clone https://github.com/tmux-plugins/tpm.git $HOME/.tmux/plugins/tpm
    if [ $? -ne 0 ]; then
        warn "Failed to clone tpm."
    fi
fi

if ! [ -d "$HOME/.zplug" ]; then
    info "Installing zplug..."
    git clone https://github.com/zplug/zplug $HOME/.zplug
    if [ $? -ne 0 ]; then
        warn "Failed to clone zplug."
    fi
fi

# copy all dotfiles
info "Extracting dotpackages..."
PWD=$(pwd)
echo "Current path: $PWD"
UBUNTU_SETUP_VERSION=$(curl -s "https://api.github.com/repos/sunipkm/ubuntu-setup/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
curl -Lo dotfiles_installer.sh "https://github.com/sunipkm/ubuntu-setup/releases/download/v$UBUNTU_SETUP_VERSION/dotfiles_installer.sh"
bash dotfiles_installer.sh
if [ $? -ne 0 ]; then
    warn "Failed to extract dotfiles, trying to copy manually..."
fi

if DEBIAN || ARCHLINUX || FEDORA; then
    # set LD_LIBRARY_PATH in .zshrc
    sed -i '/#LD_LIBRARY_PATH/c\export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib:$LD_LIBRARY_PATH' $HOME/.zshrc
elif MACOS; then
    mkdir -p $HOME/Library/Application\ Support/Code/User
    cp $HOME/.config/Code/User/settings.json $HOME/Library/Application\ Support/Code/User/
    sed -i '' "s/#LD_LIBRARY_PATH/export DYLD_LIBRARY_PATH=\/usr\/local\/lib:\/usr\/lib:\$DYLD_LIBRARY_PATH/g" $HOME/.zshrc
    sed -i '' "s/termdown/countdown/g" $HOME/.zshrc
    if [[ "$ARCH" == "arm64" ]]; then
        sed -i '' "s/#HOMEBREW_IMPORT/eval \"\$\(\/opt\/homebrew\/bin\/brew shellenv\)\"/g" $HOME/.zshrc
    else
        sed -i '' "s/#HOMEBREW_IMPORT/eval \"\$\(\/usr\/local\/bin\/brew shellenv\)\"/g" $HOME/.zshrc
    fi
    sed -i '' "s/#HOMEBREW_COMPLETIONS/fpath\=\(\$fpath \"\$HOMEBREW_PREFIX\/share\/zsh\/site-functions\"\)/g" $HOME/.zshrc
    echo 'include $HOMEBREW_CELLAR/nano/*/share/nano/*.nanorc' >>$HOME/.nanorc
fi

if ! grep -q "### NVM INIT ###" "$HOME/.zshrc"; then
    cat <<'EOF' >>"$HOME/.zshrc"
### NVM INIT ###
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
### END NVM INIT ###
EOF
fi

if ! [ -f "$HOME/.miniconda3/bin/activate" ]; then
    info "Installing python..."
    if DEBIAN || ARCHLINUX || FEDORA; then
        MINICONDA_INSTALLER=Miniconda3-latest-Linux-$ARCH.sh
    elif MACOS; then
        MINICONDA_INSTALLER=Miniconda3-latest-MacOSX-$ARCH.sh
    fi
    wget https://repo.anaconda.com/miniconda/$MINICONDA_INSTALLER
    chmod +x $MINICONDA_INSTALLER
    ./$MINICONDA_INSTALLER -b -u -p $HOME/.miniconda3
    source $HOME/.miniconda3/bin/activate
    conda config --set changeps1 false
else
    source $HOME/.miniconda3/bin/activate
fi

# necessary python packages
pip install numpy matplotlib xarray dask netcdf4 astropy scipy scikit-image natsort fortls ipykernel jupyter
pip install skmpython@git+https://github.com/sunipkm/skmpython

if WSL; then
    if command -v powershell.exe &>/dev/null; then
        info "Installing Visual Studio Code on Windows..."
        powershell.exe -NoProfile -Command "\$codeCmd = Join-Path \$env:LOCALAPPDATA 'Programs\\Microsoft VS Code\\bin\\code.cmd'; if (-not (Test-Path \$codeCmd)) { if (Get-Command winget -ErrorAction SilentlyContinue) { winget install -e --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements } else { Write-Host 'winget not found, skipping VS Code install.' } }" >/dev/null
        win_settings_source="$HOME/.config/Code/User/settings.json"
        if [ -f "$win_settings_source" ]; then
            win_settings_source_win=$(wslpath -w "$win_settings_source")
            powershell.exe -NoProfile -Command "\$dstDir = Join-Path \$env:APPDATA 'Code\\User'; New-Item -ItemType Directory -Force -Path \$dstDir | Out-Null; Copy-Item -LiteralPath '$win_settings_source_win' -Destination (Join-Path \$dstDir 'settings.json') -Force" >/dev/null
        else
            warn "Could not find $HOME/.config/Code/User/settings.json; skipping Windows VS Code settings copy."
        fi
        info "Installing VS Code extensions on Windows..."
        while read -r line; do
            powershell.exe -NoProfile -Command "\$codeCmd = Join-Path \$env:LOCALAPPDATA 'Programs\\Microsoft VS Code\\bin\\code.cmd'; if (Test-Path \$codeCmd) { & \$codeCmd --install-extension '$line' } elseif (Get-Command code -ErrorAction SilentlyContinue) { code --install-extension '$line' } else { Write-Host 'VS Code CLI not found on Windows, skipping extension install.' }" >/dev/null
        done < <(printf '%s\n' "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/extensions.txt)")
    else
        warn "powershell.exe not found, skipping Windows VS Code install from WSL."
    fi
elif INTERACTIVE; then
    if ! which code &>/dev/null; then
        info "Installing Visual Studio Code..."
        if DEBIAN; then
            sudo apt-get install -y wget gpg >/dev/null
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
            sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
            sudo apt-get install -y apt-transport-https >/dev/null
            sudo apt-get update >/dev/null
            sudo apt-get install -y code >/dev/null
            sudo apt-get -f install -y >/dev/null
        elif ARCHLINUX; then
            $INSTALL code >/dev/null
        elif FEDORA; then
            execute_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | execute_sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
            execute_sudo dnf check-update >/dev/null || true
            $INSTALL code >/dev/null || warn "Could not install code from configured Fedora repositories."
        elif MACOS; then
            brew install --cask visual-studio-code >/dev/null
            ln -s /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code ~/.local/bin/code
        fi
    fi

    info "Installing VS Code extensions..."
    while read -r line; do
        code --install-extension "$line"
    done < <(printf '%s\n' "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/extensions.txt)")
fi

if ! which node &>/dev/null; then
    if confirm "Install Node.js"; then
        info "Installing Node.js via nvm..."
        export NVM_DIR="$HOME/.nvm"
        mkdir -p "$NVM_DIR"
        if ! command -v nvm &>/dev/null; then
            NVM_VERSION=$(curl -s "https://api.github.com/repos/nvm-sh/nvm/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
            curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
        fi
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        if command -v nvm &>/dev/null; then
            nvm install --lts
            nvm alias default 'lts/*'
        else
            warn "nvm is not available after installation attempt; skipping Node.js setup."
        fi
    fi
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if ! command -v node &>/dev/null || ! command -v npm &>/dev/null || ! command -v npx &>/dev/null; then
    NODE_INSTALLED=false
else
    NODE_INSTALLED=true
fi

if $NODE_INSTALLED; then
    if ! which yarn &>/dev/null; then
        info "Installing Yarn..."
        execute_sudo "npm install --global yarn >/dev/null"
    fi
fi

if DEBIAN; then
    execute_sudo "apt-get" "install" "-y" "ttf-mscorefonts-installer"
elif ARCHLINUX; then
    $INSTALL ttf-ms-win11 >/dev/null
elif FEDORA; then
    warn "Microsoft core fonts package is not configured by default on Fedora; skipping."
fi

if DEBIAN; then
    info "Cleaning up apt cache..."
    execute_sudo apt-get autoremove -y
elif ARCHLINUX; then
    info "Cleaning up pacman cache..."
    execute_sudo pacman -Sc --noconfirm >/dev/null
elif FEDORA; then
    info "Cleaning up dnf cache..."
    execute_sudo dnf autoremove -y >/dev/null
    execute_sudo dnf clean all >/dev/null
elif MACOS; then
    info "Cleaning up Homebrew cache..."
    brew cleanup --prune all &>/dev/null
fi
