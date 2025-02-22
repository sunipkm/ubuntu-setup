#!/bin/zsh
if ! which zsh &> /dev/null; then
    echo "zsh not found, installing zsh"
    sudo apt update
    sudo apt install zsh
    chsh -s /usr/bin/zsh
    exit 1
    echo "Reboot the system before proceeding. After restarting, run terminal, and leave zsh unconfigured."
fi
USER=$(whoami)
sudo chown -R $USER:root /usr/local
sudo apt update && sudo apt upgrade
sudo apt install -y curl
sudo apt install -y build-essential pkg-config libusb-1.0-0-dev libclang-dev gfortran
if ! which kitty &> /dev/null; then
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
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator ~/.local/bin/kitty 50
fi
sudo apt install -y zoxide
sudo apt install -y fzf
sudo apt install -y eza
sudo apt install -y bat
sudo apt install -y lazygit
sudo apt install -y termdown
sudo apt install -y tmux
sudo apt install -y neovim
sudo apt install -y openssh-server openssh-client
sudo apt install -y ripgrep jq fd-find
# sudo apt install -y ibus-setup
echo "\n\nDisable the Ctrl + . weirdness using ibus-setup if on Ubuntu < 24.04.\n\n"

# bat name conflict
mkdir -p ~/.local/bin
ln -s /usr/bin/batcat ~/.local/bin/bat

# Generate ssh key
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"

# Fonts
SPWD=$(pwd)
tar -xf fonts/source_code_pro.txz -C /tmp && cd /tmp/SourceCodePro
for font_file in *.ttf *.otf; do
    sudo cp "$font_file" /usr/share/fonts/truetype/
done
cd $SPWD
tar -xf fonts/cascadia_code.txz -C /tmp && cd /tmp/CascadiaCode
for font_file in *.ttf *.otf; do
    sudo cp "$font_file" /usr/share/fonts/truetype/
done
cd $SPWD
sudo fc-cache -f -v

curl -sS https://starship.rs/install.sh | sh                                                                                                                                                                                                      ─╯
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add wasm32-unknown-unknown
rustup toolchain install nightly
cd /tmp && git clone https://github.com/mbridon/thefuck.git && pip uninstall thefuck && pip install -e ./thefuck --break-system-packages

# Lazygit
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
cd /tmp
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit -D -t /usr/local/bin/
cd $PWD

# termdown
pip3 install --break-system-packages termdown

# typst
cargo install --locked typst-cli

# copy all dotfiles
tar -xvf dotpkgs.txz -C $HOME/
cp -rv dotfiles/* $HOME/

echo "Install vscode from the website."

# miniconda
cd /tmp && wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -u -p /home/$USER/.miniconda3
source /home/$USER/.miniconda3/bin/activate
conda config --set changeps1 false

# necessary python packages
pip install numpy matplotlib xarray netcdf4 astropy scipy scikit-image natsort
pip install skmpython@git+https://github.com/sunipkm/skmpython