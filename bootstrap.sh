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

# the directory of the script
PDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    cd "$PDIR" || exit 1
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

PLATFORM=$(uname -s)
ARCH=$(uname -m)
if [[ "$PLATFORM" == "Linux" ]]; then
    echo "Detected Linux platform"
    if [[ -f /etc/debian_version ]]; then
        echo "Detected Debian-based system"
        IS_DEBIAN=true
        UPDATE="execute_sudo apt-get update -y"
        UPGRADE="execute_sudo apt-get upgrade -y"
        INSTALL="execute_sudo apt-get install -y"
        $UPDATE
        $UPGRADE
        $INSTALL git git-lfs -y &>/dev/null
        ADMIN=root
    else
        abort "This script is intended for Debian-based systems only."
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
    UPDATE=brew update
    UPGRADE=brew upgrade
    INSTALL=brew install
    ADMIN=admin
else
    abort "This script is intended for Debian Linux and macOS platforms only."
fi

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
git config --global init.defaultBranch master &> /dev/null

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

info "Setting write permissions to /usr/local..."
execute_sudo "chown" "-R" "$USER:$ADMIN" "/usr/local"
info "Package manager update..."
$UPDATE >/dev/null
info "Package manager upgrade..."
$UPGRADE >/dev/null
info "Some essential packages..."

if MACOS; then
    $INSTALL wget >/dev/null
    $INSTALL pkg-config libusb gfortran pv
elif DEBIAN; then
    $INSTALL curl >/dev/null
    $INSTALL build-essential pkg-config libusb-1.0-0-dev libclang-dev gfortran python3-pip >/dev/null
fi

if DEBIAN; then
    if ! which rsync &>/dev/null; then
        info "Installing rsync..."
        $INSTALL rsync >/dev/null
    fi
fi

info "Create local install path..."
mkdir -p ~/.local/bin >/dev/null
info "Set path to include local dir..."
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH" >/dev/null

if ! which kitty &>/dev/null; then
    info "Installing kitty..."
    if DEBIAN; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin dest=/usr/local
        # Create symbolic links to add kitty and kitten to PATH (assuming ~/.local/bin is in
        # your system-wide PATH)
        ln -sf /usr/local/kitty.app/bin/kitty /usr/local/kitty.app/bin/kitten /usr/local/bin/
        # Place the kitty.desktop file somewhere it can be found by the OS
        cp /usr/local/kitty.app/share/applications/kitty.desktop ~/.local/share/applications/
        # If you want to open text files and images in kitty via your file manager also add the kitty-open.desktop file
        cp /usr/local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
        # Update the paths to the kitty and its icon in the kitty desktop file(s)
        sed -i "s|Icon=kitty|Icon=$(readlink -f ~)/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" ~/.local/share/applications/kitty*.desktop
        sed -i "s|Exec=kitty|Exec=$(readlink -f ~)/.local/kitty.app/bin/kitty|g" ~/.local/share/applications/kitty*.desktop
        # Make xdg-terminal-exec (and hence desktop environments that support it use kitty)
        echo 'kitty.desktop' >~/.config/xdg-terminals.list
        echo "Setting kitty as default terminal..."
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/kitty 50
    elif MACOS; then
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
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
#     if [ $? -ne 0 ]; then
#         warn "Failed to install eza, trying exa..."
#     $INSTALL exa >/dev/null
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
fi

if DEBIAN; then
    $INSTALL openssh-server openssh-client >/dev/null
    $INSTALL libssl-dev >/dev/null
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
info "Installing fonts..."
NERDFONT_VERSION=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
echo "Installing nerd fonts..."
rm -vf *.ttf # delete all font files in there
echo "Downloading Cascadia Code..."
curl -Lo CascadiaCode.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/CascadiaCode.tar.xz"
tar xf CascadiaCode.tar.xz
echo "Downloading Meslo..."
curl -Lo Meslo.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/Meslo.tar.xz"
tar xf Meslo.tar.xz
for font_file in $WORK_DIR/*.ttf; do
    if DEBIAN; then
        sudo cp "$font_file" /usr/share/fonts/truetype/
    elif MACOS; then
        cp "$font_file" $HOME/Library/Fonts/
    fi
done

if DEBIAN; then
    info "Updating font cache..."
    sudo fc-cache -f -v >/dev/null
fi

if ! which starship &>/dev/null; then
    info "Installing starship..."
    curl -sSf https://starship.rs/install.sh | sh -s -- -y -b $HOME/.local/bin
fi

if confirm "Install Rust compiler"; then
    if ! [ -f "$HOME/.cargo/env" ]; then
        info "Installing rust compiler..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        . "$HOME/.cargo/env" # source cargo
    else
        . "$HOME/.cargo/env"
    fi
    confirm "Install WASM toolchain" && rustup target add wasm32-unknown-unknown
    confirm "Install nightly toolchain" && rustup toolchain install nightly
    RUST_INSTALLED=true
fi

if ! which lazygit &>/dev/null; then
    info "Installing lazygit..."
    if DEBIAN; then
        # Lazygit
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
        curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        tar xf lazygit.tar.gz lazygit
        install lazygit -D -t $HOME/.local/bin/
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
        cp -r nvim-linux-x86_64/. /usr/local
    elif MACOS; then
        $INSTALL neovim >/dev/null
    fi
fi

# termdown
if ! which termdown &>/dev/null; then
    info "Installing termdown..."
    if DEBIAN; then
        /usr/bin/python3 -m pip install --break-system-packages termdown
    elif MACOS; then
        $INSTALL countdown >/dev/null
    fi
fi

if ! which typst &>/dev/null; then
    if [ "$RUST_INSTALLED" = true ]; then
        confirm "Install Typst" && cargo install --locked typst-cli
    else
        warn "Typst requires Rust, install the Rust toolchain, then run 'cargo install --locked typst-cli' to install Typst."
    fi
fi

# Install oh-my-zsh
if ! [ -d "$HOME/.oh-my-zsh" ]; then
    info "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
fi

# Install powerlevel10k
info "Installing powerlevel10k theme for oh-my-zsh..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" &> /dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone powerlevel10k."
fi

info "Installing zsh autosuggestions..."
git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions &> /dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone zsh-autosuggestions."
fi

info "Installing zsh syntax highlighting..."
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting &> /dev/null
if [ $? -ne 0 ]; then
    warn "Failed to clone zsh-syntax-highlighting."
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

if ! [ -d "$HOME/.zplug"]; then
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

if DEBIAN; then
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
    echo 'include $HOMEBREW_CELLAR/nano/*/share/nano/*.nanorc' >>$HOME/.nanorc
fi

if ! [ -f "$HOME/.miniconda3/bin/activate" ]; then
    info "Installing python..."
    if DEBIAN; then
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
    elif MACOS; then
        brew install --cask visual-studio-code >/dev/null
        ln -s /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code ~/.local/bin/code
    fi
fi

info "Installing VS Code extensions..."
while read -r line; do
    code --install-extension "$line"
done < <(printf '%s\n' "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/extensions.txt)")

if DEBIAN; then
    info "Cleaning up apt cache..."
    execute_sudo apt-get autoremove -y
elif MACOS; then
    info "Cleaning up Homebrew cache..."
    brew cleanup --prune all &>/dev/null
fi

if ! which node &>/dev/null; then
    info "Installing Node.js..."
    if DEBIAN; then
        $INSTALL nodejs >/dev/null
        if ! which npm &>/dev/null; then
            info "Installing npm..."
            $INSTALL npm >/dev/null
        fi
    elif MACOS; then
        $INSTALL node >/dev/null
    fi
fi

if ! which yarn &>/dev/null; then
    info "Installing Yarn..."
    npm install --global yarn >/dev/null
fi

if DEBIAN; then
    if ! which zsh &>/dev/null; then
        info "zsh not found, installing zsh..."
        execute_sudo apt-get install zsh -y >/dev/null
        ohai "Enable zsh as default shell?"
        if confirm; then
            chsh -s "$(which zsh)" "$USER"
            info "zsh has been set as the default shell for $USER."
        else
            info "zsh has not been set as the default shell for $USER."
            info "You can set it later by running 'chsh -s \$(which zsh)'."
        fi
    fi
    ohai "Run the following command to install the proprietary Microsoft core fonts:"
    ohai "sudo apt-get install -y ttf-mscorefonts-installer"
fi
