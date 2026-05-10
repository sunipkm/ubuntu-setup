# Setup

Supports **Debian-based** systems (Ubuntu, Debian, Mint, …) including **WSL**, **Arch Linux**, **Fedora**, and **macOS**.

## Debian / Ubuntu / WSL

On WSL, VS Code and its extensions are installed on the **Windows** side via `winget`, and fonts are installed into the Windows user font directory.

```sh
bash -i -c "$(wget -qO- https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh)"
```

## Arch Linux / Fedora

```sh
bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh)"
```

## macOS

[Homebrew](https://brew.sh/) and Xcode command-line tools are installed automatically if missing:

```sh
bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/bootstrap.sh)"
```

---

## What Gets Installed

### Core tooling

1. `git` and `git-lfs` — sets global commit email and username.
2. `zsh` — installed and optionally set as the default shell.
3. Build essentials, per platform:
   - **Debian**: `build-essential`, `pkg-config`, `libusb-1.0-0-dev`, `libclang-dev`, `gfortran`, `cifs-utils`
   - **Arch**: `base-devel`, `pkgconf`, `libusb`, `clang`, `gcc-fortran`, `cifs-utils`
   - **Fedora**: `gcc`, `gcc-c++`, `make`, `pkgconf-pkg-config`, `libusbx-devel`, `clang`, `gcc-gfortran`, `cifs-utils`
   - **macOS**: `pkg-config`, `libusb`, `gfortran` (via Homebrew)
4. `openssh-server` / `openssh-client` (or equivalent) — generates an ED25519 SSH key.
5. Creates `~/.local/bin` and adds it to `PATH`.

### Quality-of-life packages

| Tool                                               | Description                                                                              |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [zoxide](https://github.com/ajeetdsouza/zoxide)    | Smarter `cd`                                                                             |
| [fzf](https://github.com/junegunn/fzf)             | Fuzzy finder                                                                             |
| [eza](https://github.com/eza-community/eza)        | Modern `ls` replacement                                                                  |
| [bat](https://github.com/sharkdp/bat)              | `cat` with syntax highlighting (Debian: `bat` symlink fixes name conflict with `batcat`) |
| [tmux](https://github.com/tmux/tmux/wiki)          | Terminal multiplexer                                                                     |
| [ripgrep](https://github.com/BurntSushi/ripgrep)   | Fast `grep` replacement                                                                  |
| [jq](https://jqlang.org/)                          | JSON processor                                                                           |
| [btop](https://github.com/aristocratsoftware/btop) | Resource monitor                                                                         |
| [fd](https://github.com/sharkdp/fd)                | Fast `find` replacement (Debian: `fd-find` with `fd` symlink)                            |

### Terminal & shell

- [kitty](https://sw.kovidgoyal.net/kitty/) — installed on interactive (non-WSL) systems; set as default terminal emulator on Debian.
- [oh-my-zsh](https://ohmyzsh.sh/) with the [powerlevel10k](https://github.com/romkatv/powerlevel10k) theme.
- zsh plugins: [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting), [fzf-tab](https://github.com/Aloxaf/fzf-tab).
- [zplug](https://github.com/zplug/zplug) plugin manager.
- [starship](https://starship.rs/) prompt.

### tmux plugins

- [Catppuccin theme for tmux](https://github.com/catppuccin/tmux)
- [tmuxifier](https://github.com/jimeh/tmuxifier)
- [TPM — Tmux Plugin Manager](https://github.com/tmux-plugins/tpm)

### Editor & IDE

- [Neovim](https://neovim.io/) — latest release binary on Debian; package manager on Arch/Fedora/macOS.
- [Visual Studio Code](https://code.visualstudio.com/) — installed on interactive systems (or on Windows from WSL), with extensions from `extensions.txt`.

### Fonts (interactive and WSL systems)

- **CaskaydiaCove Nerd Font** and **Meslo LGS Nerd Font** (from [Nerd Fonts](https://www.nerdfonts.com/)).
- **Aptos** (Microsoft, Debian only).
- **Microsoft Core Fonts** (Debian and Arch via `yay`).

### Languages & runtimes

- **Rust** (optional) — via `rustup`; optionally adds WASM and nightly toolchains.
- **Typst** (optional, requires Rust) — built via `cargo install --locked typst-cli`.
- **Python** — [Miniconda](https://docs.anaconda.com/miniconda/) with packages: `numpy`, `matplotlib`, `xarray`, `dask`, `netcdf4`, `astropy`, `scipy`, `scikit-image`, `natsort`, `fortls`, `ipykernel`, `jupyter`, `skmpython`.
- **Node.js** (optional) — via [nvm](https://github.com/nvm-sh/nvm) (LTS), with [Yarn](https://yarnpkg.com/).

### Other tools

- [lazygit](https://github.com/jesseduffield/lazygit) — TUI git client.
- [termdown](https://github.com/trehn/termdown) (Linux) / `countdown` (macOS) — terminal countdown timer.
- [Podman](https://podman.io/) (optional) — container runtime.
- [`cross`](https://github.com/cross-rs/cross) (optional, requires Rust + Podman) — cross-compilation tool.
- Dotfiles copied to `~/`.

### Testing
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows/setup.ps1 | iex
```