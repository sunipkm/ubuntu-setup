# Setup
## Debian-based Systems
Execute the following command to get started:
```sh
sudo apt-get update && sudo apt-get install -y curl
bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh)"
```

## macOS
```sh
bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh)"
```

## Operations
1. Installs `git` and `git-lfs`, then sets up global commit email and username for git.
2. Upgrades packages, and installs essentials:
   1. `build-essential`
   2. `pkg-config`
   3. `libusb-1.0-0-dev`
   4. `libclang-dev`
   5. `gfortran`
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
   12. Nerd fonts (Cascadia Code and Source Code Pro), Aptos (Debian).
   13. Installs [starship](https://starship.rs/).
   14. Installs the Rust toolchain.
   15. Installs [lazygit](https://github.com/jesseduffield/lazygit).
   16. Installs [termdown](https://github.com/trehn/termdown).
   17. Copies all the necessary dotfiles to `~/`.
   18. Installs [miniconda](https://docs.anaconda.com/miniconda/).
   19. Installs basic python packages (`numpy`, `matplotlib`, `xarray`, `netcdf4`, `astropy`, `scipy`, `scikit-image`, `natsort`, `fortls`, `ipykernel`, `skmpython`).
   1. Installs [thefuck]
   1. Installs [`vscode`](https://code.visualstudio.com/) and necessary extensions.
   1. Installs the `zsh` shell, and sets it as the default shell.
   2. Installs Docker.
   3. Installs Rust compiler, optionally WASM and nightly toolchains, typst, and [`cross`](https://github.com/cross-rs/cross) if Docker is installed.
6.  Fixes the `bat` command name conflict.
7.  Generates an ED25519 key.