#!/bin/bash
# the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# the temp directory used, within $DIR
# omit the -p parameter to create a temporal directory in the default location
WORK_DIR=`mktemp -d`

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

echo "Setting write permission to /usr/local..."
sudo chown -R $USER:root /usr/local > /dev/null
echo "System upgrade..."
sudo apt update && sudo apt upgrade -y
echo "Some essential packages..."
sudo apt-get install -y curl > /dev/null
sudo apt-get install -y build-essential pkg-config libusb-1.0-0-dev libclang-dev gfortran python3-pip > /dev/null
echo "Create local install path..."
mkdir -p ~/.local/bin > /dev/null
echo "Set path to include local dir..."
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH" > /dev/null
if ! which kitty &> /dev/null; then
    echo "Installing kitty..."
    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
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
    echo 'kitty.desktop' > ~/.config/xdg-terminals.list
    echo "Setting kitty as default terminal..."
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator ~/.local/bin/kitty 50
fi
echo "Some QoL dependencies..."
sudo apt-get install -y zoxide > /dev/null
sudo apt-get install -y fzf > /dev/null
sudo apt-get install -y eza > /dev/null
sudo apt-get install -y bat > /dev/null
sudo apt-get install -y tmux > /dev/null
sudo apt-get install -y neovim > /dev/null
sudo apt-get install -y openssh-server openssh-client > /dev/null
sudo apt-get install -y ripgrep jq fd-find > /dev/null
sudo apt-get install -y libssl-dev > /dev/null
# sudo apt install -y ibus-setup

# bat name conflict
mkdir -p ~/.local/bin > /dev/null
ln -s /usr/bin/batcat ~/.local/bin/bat &> /dev/null

# Generate ssh key
if ! [ -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating ssh key with the ed25519 algorithm..."
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
fi

# Fonts
echo "Installing fonts..."
NERDFONT_VERSION=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
echo "Installing nerd fonts..."
cd $WORK_DIR
rm -vf *.ttf # delete all font files in there
echo "Downloading Cascadia Code..."
curl -Lo CascadiaCode.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/CascadiaCode.tar.xz"
tar xf CascadiaCode.tar.xz
echo "Downloading SourceCodePro..."
curl -Lo SourceCodePro.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/SourceCodePro.tar.xz"
tar xf SourceCodePro.tar.xz
for font_file in $WORK_DIR/*.ttf; do
    sudo cp "$font_file" /usr/share/fonts/truetype/
done
cd $DIR
echo "Updating font cache..."
sudo fc-cache -f -v > /dev/null

if ! which starship &> /dev/null; then
    echo "Installing starship..."
    curl -sSf https://starship.rs/install.sh | sh
fi

if ! [ -f "$HOME/.cargo/env" ]; then
    echo "Installing rust compiler..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    . "$HOME/.cargo/env" # source cargo
    rustup target add wasm32-unknown-unknown
    rustup toolchain install nightly
else
    . "$HOME/.cargo/env"
fi

# Lazygit
if ! which lazygit &> /dev/null; then
    echo "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
    cd $WORK_DIR
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    install lazygit -D -t /usr/local/bin/
    cd $DIR
fi

# termdown
if ! which termdown &> /dev/null; then
    echo "Installing termdown..."
    /usr/bin/python3 -m pip install --break-system-packages termdown
fi

# typst
echo "Installing typst..."
if ! which typst &> /dev/null; then
    cargo install --locked typst-cli
fi

# copy all dotfiles
echo "Extracting dotpackages..."
tar -xf $DIR/dotpkgs.txz -C $HOME/
echo "Copying dotfiles..."
cp -r $DIR/dotfiles/. $HOME/


# miniconda
if ! [ -f "/home/$USER/.miniconda3/bin/activate" ]; then
    echo "Installing python..."
    cd $WORK_DIR && wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    chmod +x Miniconda3-latest-Linux-x86_64.sh
    ./Miniconda3-latest-Linux-x86_64.sh -b -u -p /home/$USER/.miniconda3
    source /home/$USER/.miniconda3/bin/activate
    conda config --set changeps1 false
    cd $DIR
else
    source /home/$USER/.miniconda3/bin/activate
fi

# necessary python packages
pip install numpy matplotlib xarray netcdf4 astropy scipy scikit-image natsort fortls
pip install skmpython@git+https://github.com/sunipkm/skmpython

if ! which thefuck &> /dev/null; then
    echo "Installing thefuck..."
    cd $WORK_DIR && rm -rf thefuck && git clone https://github.com/mbridon/thefuck.git && pip uninstall thefuck && pip install -e ./thefuck && cd $DIR
fi

echo -e "\n\nDisable the Ctrl + . weirdness using ibus-setup if on Ubuntu < 24.04.\n\n"
echo "Install vscode from the website."

if ! which zsh &> /dev/null; then
    echo "zsh not found, installing zsh"
    sudo apt update
    sudo apt install zsh
    chsh -s /usr/bin/zsh
    echo "Reboot the system before proceeding. After restarting, run terminal, and leave zsh unconfigured."
    exit 1
fi