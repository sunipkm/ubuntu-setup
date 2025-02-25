# Ubuntu Setup
Execute the following command to get started:
```sh
sudo apt-get update && sudo apt-get install -y curl \
curl -sS https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh | bash
```

## Operations
1. Installs `git` and `git-lfs`, then sets up global commit email and username for git.
2. Upgrades packages, and installs essentials:
   1. `curl`
   2. `build-essential`
   3. `pkg-config`
   4. `libusb-1.0-0-dev`
   5. `libclang-dev`
   6. `gfortran`
   7. `python3-pip`
3. Creates a local bin directory (`~/.local/bin`) and adds it to path.
4. Installs the [`kitty`](https://sw.kovidgoyal.net/kitty/) terminal, and sets it up as the default terminal emulator.
5. Installs some quality-of-life packages:
   1. [zoxide](https://github.com/ajeetdsouza/zoxide)
   2. [fzf](https://github.com/junegunn/fzf)
   3. [eza](https://github.com/eza-community/eza)
   4. [bat](https://github.com/sharkdp/bat)
   5. [tmux](https://github.com/tmux/tmux/wiki)
   6. [neovim](https://neovim.io/)
   7. `openssh-server` and `openssh-client`
   8. [ripgrep](https://github.com/BurntSushi/ripgrep)
   9. [jq](https://jqlang.org/)
   10. [fd-find](https://github.com/sharkdp/fd)
   11. `libssl-dev` (dependency of `typst`)
6.  Fixes the `bat` command name conflict.
7.  Generates an ED25519 key.
8.  Installs nerd fonts (Cascadia Code and Source Code Pro).
9.  Installs [starship](https://starship.rs/).
10. Installs the Rust toolchain.
11. Installs [lazygit](https://github.com/jesseduffield/lazygit).
12. Installs [termdown](https://github.com/trehn/termdown).
13. Copies all the necessary dotfiles to `~/`.
14. Installs [miniconda](https://docs.anaconda.com/miniconda/).
15. Installs basic python packages (`numpy`, `matplotlib`, `xarray`, `netcdf4`, `astropy`, `scipy`, `scikit-image`, `natsort`, `fortls`, `ipykernel`, `skmpython`).
16. Installs [thefuck]
17. Installs [`vscode`](https://code.visualstudio.com/) and necessary extensions.
18. Installs the `zsh` shell, and sets it as the default shell.