# Setup

Supports **Debian-based** systems (Ubuntu, Debian, Mint, …) including **WSL**, **Arch Linux**, **Fedora**, and **macOS**.

## Quick start (all platforms)

Run `setup.sh` to launch an interactive configuration wizard and optionally kick off the full installation in one step:

```sh
bash -i -c "$(curl -fsSL https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/setup.sh)"
```

On Ubuntu/Debian you can also use `wget`:

```sh
bash -i -c "$(wget -qO- https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/setup.sh)"
```

> **WSL note:** VS Code and its extensions are installed on the **Windows** side via `winget`, and fonts are installed into the Windows user font directory.

> **macOS note:** [Homebrew](https://brew.sh/) and Xcode command-line tools are installed automatically if missing.

## Snapshots

`snapshot.sh` captures the current machine's full personalisation into a single self-contained, portable script that can reproduce the setup on a fresh machine.

### What gets bundled

- `~/.setup.conf` — install settings (from `configure.sh`); if absent, the script auto-detects the installed tools and reconstructs it.
- **GPG secret keys** — exported non-interactively (key is still passphrase-protected; nothing is stored in the clear).
- **SSH keys** — `id_*`, `*.pub`, `config`, `authorized_keys`, `known_hosts`.
- **VS Code extensions** — captured via `code --list-extensions`.
- **Live dotfiles** — `~/.zshrc`, `~/.tmux.conf`, `~/.p10k.zsh`, `~/.nanorc`, `~/.fzf_zsh`, and `~/.config/{kitty,nvim,tmux,lazygit,starship.toml,yazi,…}`.
- **Optional config files** — any of the following that exist are offered via an interactive checklist (or per-file y/n prompts if `dialog` is unavailable):

  | File | Contents |
  |---|---|
  | `~/.pypirc` | PyPI credentials |
  | `~/.wakatime.cfg` | WakaTime API key / config |
  | `~/.npmrc` | npm credentials / registry config |
  | `~/.netrc` | Generic network credentials |
  | `~/.cargo/credentials.toml` | Cargo registry credentials |
  | `~/.aws/credentials` | AWS credentials |
  | `~/.aws/config` | AWS config |

  All optional files are restored with `chmod 600` permissions.

### Creating a snapshot

```sh
bash snapshot.sh                     # writes ~/snapshot-<hostname>-<date>.sh
bash snapshot.sh ~/my-snapshot.sh    # custom output path
```

### Restoring on a fresh machine

Running the generated snapshot script will:

1. Restore GPG and SSH keys.
2. Write `~/.setup.conf` with all previous settings.
3. Install VS Code extensions (if `code` is on `PATH`).
4. Call `setup.sh` → `configure.sh` (pre-answered via environment variables) → `install.sh`.

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

---

## Windows (native)

A PowerShell wizard installs a full developer environment on Windows 10 (Build 17763 / 1809) and Windows 11.
WSL 2 requires Build 19041 (Windows 10 2004) or later.

### Quick start

Open **PowerShell as Administrator** and run:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/windows/setup.ps1 | iex"
```

### Installation flow

**Phase 1 — runs immediately:**

1. Self-elevates to Administrator if needed.
2. Validates the Windows build (>= 17763).
3. Ensures `winget` (App Installer) is available.
4. Installs **Git for Windows** via winget.
5. Enables the **WSL** and **Virtual Machine Platform** Windows optional features (DISM — no Store required).
6. Stages the setup scripts to `C:\ProgramData\ubuntu-setup\` so they survive the reboot.
7. Registers a one-shot logon scheduled task (`UbuntuSetupResume`) to continue after reboot.
8. **Reboots** (10-second countdown, Ctrl+C to cancel).

**Phase 2 — runs automatically after login:**

1. The scheduled task fires `setup.ps1 -Resume` and unregisters itself.
2. The **WinForms configuration wizard** opens and collects:
   - Hostname, Git name / email
   - Optional GPG secret key file
   - WSL distribution, Linux username & password
   - Optional components (Rust, Node.js, Podman, …)
3. The **unattended installer** (`install.ps1`) runs and:
   - Installs **VS Code** and all extensions from `extensions.txt`.
   - Installs **Nerd Fonts** (CaskaydiaCove, Meslo LGS) and **Aptos** into the Windows user font directory.
   - Installs the selected WSL distribution, creates the Linux user, imports GPG key, copies SSH keys.
   - Runs `wsl_bootstrap.sh` inside WSL to install the full Linux toolchain (same packages as the Linux flow above).

### Requirements

| Requirement | Minimum |
|---|---|
| Windows | 10 Build 17763 (1809) |
| WSL 2 | 10 Build 19041 (2004) |
| winget | App Installer from the Microsoft Store |
| PowerShell | 5.1 (built-in `powershell.exe`) |