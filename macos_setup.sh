#!/bin/bash
# the directory of the script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    rm -rf "$WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

# Architecture
ARCH=$(uname -m)

# Homebrew path

if [[ "$ARCH" == "arm64" ]]; then
    echo "Detected ARM64 architecture"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Detected x86_64 architecture"
    eval "$(/usr/local/bin/brew shellenv)"
fi

echo "Brew update..."
brew update >/dev/null
echo "Brew upgrade..."
brew upgrade >/dev/null
echo "Some essential packages..."
brew install wget
brew install pkg-config libusb gfortran
echo "Create local install path..."
mkdir -p ~/.local/bin >/dev/null
echo "Set path to include local dir..."
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH" >/dev/null
if ! which kitty &>/dev/null; then
    echo "Installing kitty..."
    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
fi
echo "Some QoL dependencies..."
echo "Installing zoxide..."
brew install zoxide >/dev/null
echo "Installing fzf..."
brew install fzf >/dev/null
echo "Installing eza..."
brew install eza >/dev/null
echo "Installing bat..."
brew install bat >/dev/null
echo "Installing tmux..."
brew install tmux >/dev/null
echo "Installing ripgrep, jq, fd..."
brew install ripgrep jq fd >/dev/null
echo "Installing openssl..."
brew install openssl >/dev/null
echo "Installing nano..."
brew install nano >/dev/null

echo '$HOMEBREW_CELLAR/nano/*/share/nano/*.nanorc' >>$HOME/.nanorc

# Generate ssh key
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating ssh key with the ed25519 algorithm..."
    ssh-keygen -t ed25519 -C "$(git config --global user.email)"
fi

# Fonts
echo "Installing fonts..."
NERDFONT_VERSION=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep tag_name | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
echo "Installing nerd fonts..."
cd $WORK_DIR
rm -vf *.ttf # delete all font files in there
echo "Downloading Cascadia Code..."
curl -Lo CascadiaCode.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/CascadiaCode.tar.xz"
tar xf CascadiaCode.tar.xz
echo "Downloading Meslo..."
curl -Lo Meslo.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/Meslo.tar.xz"
tar xf Meslo.tar.xz
for font_file in $WORK_DIR/*.ttf; do
    sudo cp "$font_file" $HOME/Library/Fonts/
done
cd $DIR

if ! which starship &>/dev/null; then
    echo "Installing starship..."
    curl -sSf https://starship.rs/install.sh | sh -s -- -y
fi

if ! [ -f "$HOME/.cargo/env" ]; then
    echo "Installing rust compiler..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env" # source cargo
    rustup target add wasm32-unknown-unknown
    rustup toolchain install nightly
else
    . "$HOME/.cargo/env"
fi

# Lazygit
if ! which lazygit &>/dev/null; then
    echo "Installing lazygit..."
    brew install lazygit >/dev/null
fi

if ! which nvim &>/dev/null; then
    echo "Installing neovim..."
    brew install neovim >/dev/null
fi

# termdown
if ! which termdown &>/dev/null; then
    echo "Installing termdown..."
    brew install termdown >/dev/null
fi

# typst
echo "Installing typst..."
if ! which typst &>/dev/null; then
    cargo install --locked typst-cli
fi

# copy all dotfiles
echo "Extracting dotpackages..."
tar -xf $DIR/dotpkgs.txz -C $HOME/
echo "Copying dotfiles..."
cp -r $DIR/dotfiles/. $HOME/

sed -i '/#LD_LIBRARY_PATH/c\export DYLD_LIBRARY_PATH=/usr/local/lib:/usr/lib:\$DYLD_LIBRARY_PATH' $HOME/.zshrc

# miniconda
if ! [ -f "$HOME/.miniconda3/bin/activate" ]; then
    echo "Installing python..."
    cd $WORK_DIR && wget https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-$ARCH.sh
    chmod +x Miniconda3-latest-MacOSX-$ARCH.sh
    ./Miniconda3-latest-MacOSX-$ARCH.sh -b -u -p $HOME/.miniconda3
    source $HOME/.miniconda3/bin/activate
    conda config --set changeps1 false
    cd $DIR
else
    source $HOME/.miniconda3/bin/activate
fi

# necessary python packages
pip install numpy matplotlib xarray netcdf4 astropy scipy scikit-image natsort fortls ipykernel jupyter
pip install skmpython@git+https://github.com/sunipkm/skmpython

# if ! which thefuck &> /dev/null; then
#     echo "Installing thefuck..."
#     cd $WORK_DIR && rm -rf thefuck && git clone https://github.com/mbridon/thefuck.git && pip uninstall thefuck && pip install -e ./thefuck && cd $DIR
# fi

if ! which code &>/dev/null; then
    echo "Installing vscode..."
    brew install --cask visual-studio-code >/dev/null
    ln -s /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code ~/.local/bin/code
    while read -r line; do
        code --install-extension "$line"
    done <"extensions.txt"
fi

# nodejs and yarn
if ! which node &>/dev/null; then
    echo "Installing nodejs..."
    brew install node >/dev/null
fi

if ! which yarn &>/dev/null; then
    echo "Installing yarn..."
    npm install --global yarn >/dev/null
fi
