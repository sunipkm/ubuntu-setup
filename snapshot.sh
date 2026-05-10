#!/usr/bin/env bash
# snapshot.sh — Captures the current machine's personalisation into a single
# self-contained, self-executing script ("snapshot").
#
# The snapshot bundles:
#   • ~/.setup.conf            install settings (from configure.sh)
#   • GPG secret key           exported non-interactively
#   • SSH keys                 id_*, *.pub, config, authorized_keys, known_hosts
#   • VS Code extensions       captured via `code --list-extensions`
#   • Live dotfiles owned by this repo:
#       ~/.zshrc  ~/.tmux.conf  ~/.p10k.zsh  ~/.nanorc  ~/.fzf_zsh
#       ~/.config/{kitty,nvim,tmux,lazygit,starship.toml,yazi,…}
#
# Running the generated snapshot script on a fresh machine:
#   1. Restores GPG key + SSH keys
#   2. Writes ~/.setup.conf with all previous settings
#   3. Installs VS Code extensions (if `code` is on PATH)
#   4. Calls setup.sh → configure.sh (pre-answered via env) → install.sh
#
# Usage:
#   bash snapshot.sh [OUTPUT_SCRIPT]
#   bash snapshot.sh ~/my-snapshot.sh
#
# The output file defaults to ~/ubuntu-setup-snapshot-<date>.sh

set -uo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then tty_escape() { printf "\033[%sm" "$1"; }
else               tty_escape() { :; }; fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"; tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"; tty_reset="$(tty_escape 0)"
ohai()  { printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$*"; }
info()  { printf "${tty_blue}INFO${tty_reset}: %s\n" "$*"; }
warn()  { printf "[${tty_red}WARN${tty_reset}] %s\n" "$*" >&2; }
abort() { printf "%s\n" "$*" >&2; exit 1; }

# ── Script dir (repo root) ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Output file ───────────────────────────────────────────────────────────────
DATESTAMP=$(date +"%Y%m%d-%H%M%S")
SNAPHOST=$(hostname 2>/dev/null | tr ' ' '-')
OUTPUT="${1:-$HOME/snapshot-${SNAPHOST}-${DATESTAMP}.sh}"

# ── Temp workspace ─────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
STAGE="$WORK_DIR/stage"   # directory tree that gets tar'd + base64'd
mkdir -p "$STAGE"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────────
# 1. CONFIG FILE
# ──────────────────────────────────────────────────────────────────────────────
ohai "Capturing ~/.setup.conf"
if [[ -f "$HOME/.setup.conf" ]]; then
    cp "$HOME/.setup.conf" "$STAGE/setup.conf"
    info "Included ~/.setup.conf"
else
    warn "~/.setup.conf not found — snapshot will prompt configure.sh interactively."
    touch "$STAGE/setup.conf"   # empty placeholder; setup.sh will re-run the TUI
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. GPG SECRET KEY
# ──────────────────────────────────────────────────────────────────────────────
ohai "Exporting GPG secret keys"
GPG_FINGERPRINTS=$(gpg --list-secret-keys --with-colons 2>/dev/null \
    | awk -F: '/^fpr/{print $10}')

if [[ -n "$GPG_FINGERPRINTS" ]]; then
    GPG_EXPORT_FILE="$STAGE/gpg-secret.asc"
    # Export all secret keys; the user will be prompted for each key's passphrase
    # by the gpg agent — nothing is stored unprotected.
    if gpg --batch --armor --export-secret-keys $GPG_FINGERPRINTS \
            > "$GPG_EXPORT_FILE" 2>/dev/null; then
        info "Exported GPG secret key(s): $(echo "$GPG_FINGERPRINTS" | tr '\n' ' ')"
    else
        warn "gpg export failed; GPG key will not be in the snapshot."
        rm -f "$GPG_EXPORT_FILE"
    fi
else
    warn "No GPG secret keys found in keyring; skipping."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. SSH KEYS
# ──────────────────────────────────────────────────────────────────────────────
ohai "Capturing SSH keys"
SSH_STAGE="$STAGE/ssh"
mkdir -p "$SSH_STAGE"
SSH_FILES_COPIED=0

for _f in \
    "$HOME"/.ssh/id_* \
    "$HOME"/.ssh/*.pub \
    "$HOME/.ssh/config" \
    "$HOME/.ssh/authorized_keys" \
    "$HOME/.ssh/known_hosts"; do
    [[ -f "$_f" ]] || continue
    cp "$_f" "$SSH_STAGE/$(basename "$_f")"
    (( SSH_FILES_COPIED++ ))
done

if (( SSH_FILES_COPIED > 0 )); then
    info "Copied $SSH_FILES_COPIED SSH file(s)"
else
    warn "No SSH files found in ~/.ssh — skipping."
    rmdir "$SSH_STAGE"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. REPO-OWNED DOTFILES (live versions from $HOME)
# ──────────────────────────────────────────────────────────────────────────────
ohai "Capturing repo-owned dotfiles"
DOTS_STAGE="$STAGE/dotfiles"
mkdir -p "$DOTS_STAGE"

# Flat dotfiles tracked by this repo
REPO_DOTFILES=(
    .zshrc
    .tmux.conf
    .p10k.zsh
    .nanorc
    .fzf_zsh
)
for _dot in "${REPO_DOTFILES[@]}"; do
    if [[ -f "$HOME/$_dot" ]]; then
        cp "$HOME/$_dot" "$DOTS_STAGE/$_dot"
        info "  $HOME/$_dot"
    fi
done

# .config subdirectories owned by this repo
# Derived from the repo's dotfiles/.config/ tree.
REPO_CONFIG_DIRS=()
if [[ -d "$SCRIPT_DIR/dotfiles/.config" ]]; then
    while IFS= read -r -d '' _d; do
        _name=$(basename "$_d")
        REPO_CONFIG_DIRS+=("$_name")
    done < <(find "$SCRIPT_DIR/dotfiles/.config" -mindepth 1 -maxdepth 1 -type d -print0)
fi
# starship.toml lives directly in .config, not in a subdir
if [[ -f "$SCRIPT_DIR/dotfiles/.config/starship.toml" ]]; then
    mkdir -p "$DOTS_STAGE/.config"
    [[ -f "$HOME/.config/starship.toml" ]] && \
        cp "$HOME/.config/starship.toml" "$DOTS_STAGE/.config/starship.toml" && \
        info "  $HOME/.config/starship.toml"
fi

for _dir in "${REPO_CONFIG_DIRS[@]}"; do
    if [[ -d "$HOME/.config/$_dir" ]]; then
        mkdir -p "$DOTS_STAGE/.config"
        cp -r "$HOME/.config/$_dir" "$DOTS_STAGE/.config/$_dir"
        info "  $HOME/.config/$_dir/"
    fi
done

# VS Code settings in non-standard locations
# Arch (code-oss from official repos) uses "Code - OSS" instead of "Code"
if [[ -d "$HOME/.config/Code - OSS" ]]; then
    mkdir -p "$DOTS_STAGE/.config/Code - OSS"
    cp -r "$HOME/.config/Code - OSS/." "$DOTS_STAGE/.config/Code - OSS/"
    info "  $HOME/.config/Code - OSS/ (Arch code-oss)"
fi
# macOS stores VS Code settings under ~/Library/Application Support/Code/
if [[ -d "$HOME/Library/Application Support/Code" ]]; then
    mkdir -p "$DOTS_STAGE/Library/Application Support/Code"
    cp -r "$HOME/Library/Application Support/Code/." \
        "$DOTS_STAGE/Library/Application Support/Code/"
    info "  $HOME/Library/Application Support/Code/ (macOS)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5. VSCODE EXTENSIONS
# ──────────────────────────────────────────────────────────────────────────────
ohai "Capturing VS Code extensions"
VSCODE_EXT_FILE="$STAGE/vscode-extensions.txt"
for _code_bin in code code-insiders codium; do
    if command -v "$_code_bin" &>/dev/null; then
        "$_code_bin" --list-extensions 2>/dev/null > "$VSCODE_EXT_FILE" && break
    fi
done
if [[ -s "$VSCODE_EXT_FILE" ]]; then
    EXT_COUNT=$(wc -l < "$VSCODE_EXT_FILE" | tr -d ' ')
    info "Captured $EXT_COUNT VS Code extension(s)"
else
    warn "VS Code not found or no extensions detected; skipping."
    rm -f "$VSCODE_EXT_FILE"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6. BUILD THE PAYLOAD
# ──────────────────────────────────────────────────────────────────────────────
ohai "Building payload archive"
PAYLOAD_TAR="$WORK_DIR/payload.tar.gz"
PAYLOAD_B64="$WORK_DIR/payload.b64"

# Paths relative to $STAGE so the archive unpacks cleanly
(cd "$STAGE" && tar -czf "$PAYLOAD_TAR" .)
base64 < "$PAYLOAD_TAR" > "$PAYLOAD_B64"

# ──────────────────────────────────────────────────────────────────────────────
# 6. WRITE THE SELF-EXTRACTING SNAPSHOT SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
ohai "Writing snapshot script to $OUTPUT"

# Read the config so we can embed it verbatim in the restore header for clarity.
CONF_PREVIEW=""
if [[ -s "$STAGE/setup.conf" ]]; then
    CONF_PREVIEW=$(grep -v '^#' "$STAGE/setup.conf" | grep -v '^$' | head -30)
fi

cat > "$OUTPUT" <<'HEADER'
#!/usr/bin/env bash
# ubuntu-setup snapshot — generated by snapshot.sh
# Run this on a fresh machine to fully reproduce the captured environment:
#
#   bash <snapshot>.sh
#
# What this does:
#   1. Detects platform, installs prerequisites (git, gnupg, dialog)
#   2. Restores GPG secret key  → imports into keyring
#   3. Restores SSH keys        → copies to ~/.ssh with correct permissions
#   4. Writes ~/.setup.conf     → pre-fills all install settings
#   5. Restores live dotfiles   → ~/.zshrc, ~/.tmux.conf, ~/.config/…
#   6. Installs VS Code extensions (requires `code` on PATH)
#   7. Calls setup.sh / install.sh for the full unattended install

set -uo pipefail

HEADER

# Embed the generation timestamp and config preview as a comment block
cat >> "$OUTPUT" <<METADATA
# ── Snapshot metadata ──────────────────────────────────────────────────────────
# Generated : $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Host      : $(hostname)
# User      : $(whoami)
# Platform  : $(uname -s) / $(uname -m)
#
# Embedded settings:
$(echo "$CONF_PREVIEW" | sed 's/^/#   /')
# ──────────────────────────────────────────────────────────────────────────────

METADATA

# Append the restore logic
cat >> "$OUTPUT" <<'RESTORE_SCRIPT'
# ── Colour helpers ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then tty_escape() { printf "\033[%sm" "$1"; }
else               tty_escape() { :; }; fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"; tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"; tty_reset="$(tty_escape 0)"
ohai()  { printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$*"; }
info()  { printf "${tty_blue}INFO${tty_reset}: %s\n" "$*"; }
warn()  { printf "[${tty_red}WARN${tty_reset}] %s\n" "$*" >&2; }
abort() { printf "%s\n" "$*" >&2; exit 1; }

PLATFORM=$(uname -s)
ARCH=$(uname -m)

# ── Prerequisites ─────────────────────────────────────────────────────────────
ohai "Installing prerequisites"
if [[ "$PLATFORM" == "Linux" ]]; then
    if [[ -f /etc/debian_version ]]; then
        sudo apt-get update -y >/dev/null
        sudo apt-get install -y git gnupg dialog curl >/dev/null
    elif [[ -f /etc/arch-release ]]; then
        sudo pacman -Sy --noconfirm >/dev/null
        sudo pacman -S --noconfirm --needed git gnupg dialog curl >/dev/null
    elif [[ -f /etc/fedora-release ]]; then
        sudo dnf makecache -y >/dev/null
        sudo dnf install -y git gnupg2 dialog curl >/dev/null
    else
        abort "Unsupported Linux distribution."
    fi
elif [[ "$PLATFORM" == "Darwin" ]]; then
    if ! xcode-select -p &>/dev/null; then
        xcode-select --install
        until xcode-select --print-path &>/dev/null; do sleep 5; done
    fi
    if ! command -v brew &>/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    if [[ "$ARCH" == "arm64" ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; \
    else eval "$(/usr/local/bin/brew shellenv)"; fi
    brew install dialog curl >/dev/null
else
    abort "Unsupported platform: $PLATFORM"
fi

# ── Extract payload ───────────────────────────────────────────────────────────
SCRIPT_END=$(grep --max-count 2 --line-number ___END_OF_SNAPSHOT___ "$0" \
    | cut -f1 -d: | tail -1) || abort "Payload marker not found."
(( SCRIPT_END += 1 ))

WORK_DIR=$(mktemp -d)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

ohai "Extracting payload"
tail -n +"$SCRIPT_END" "$0" | base64 -d | tar -xz -C "$WORK_DIR"

# ── Restore GPG key ────────────────────────────────────────────────────────────
if [[ -f "$WORK_DIR/gpg-secret.asc" ]]; then
    ohai "Restoring GPG key"
    if gpg --batch --import "$WORK_DIR/gpg-secret.asc"; then
        GPG_FINGERPRINT=$(gpg --list-secret-keys --with-colons 2>/dev/null \
            | awk -F: '/^fpr/{print $10; exit}')
        if [[ -n "$GPG_FINGERPRINT" ]]; then
            _GPG_UID=$(gpg --list-secret-keys --with-colons "$GPG_FINGERPRINT" 2>/dev/null \
                | awk -F: '/^uid/{print $10; exit}')
            _GIT_NAME=$(echo "$_GPG_UID"  | sed 's/ <.*//')
            _GIT_EMAIL=$(echo "$_GPG_UID" | sed 's/.*<\(.*\)>/\1/')
            git config --global user.name        "$_GIT_NAME"
            git config --global user.email       "$_GIT_EMAIL"
            git config --global user.signingkey  "$GPG_FINGERPRINT"
            git config --global commit.gpgsign   true
            git config --global init.defaultBranch master 2>/dev/null || true
            info "GPG key imported: $_GPG_UID ($GPG_FINGERPRINT)"
            info "Git configured with signing key"
        fi
    else
        warn "GPG import failed — continuing without signing key."
    fi
else
    info "No GPG key in payload; skipping."
fi

# ── Restore SSH keys ──────────────────────────────────────────────────────────
if [[ -d "$WORK_DIR/ssh" ]]; then
    ohai "Restoring SSH keys"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    for _f in "$WORK_DIR/ssh"/*; do
        [[ -f "$_f" ]] || continue
        _dst="$HOME/.ssh/$(basename "$_f")"
        cp "$_f" "$_dst"
        case "$(basename "$_f")" in
            *.pub|config|authorized_keys|known_hosts) chmod 644 "$_dst" ;;
            *)                                         chmod 600 "$_dst" ;;
        esac
        info "  $(basename "$_f")"
    done
fi

# ── Restore dotfiles ──────────────────────────────────────────────────────────
if [[ -d "$WORK_DIR/dotfiles" ]]; then
    ohai "Restoring dotfiles"
    rsync -a --no-times "$WORK_DIR/dotfiles/" "$HOME/"
    info "Dotfiles restored to $HOME"
fi

# ── Write ~/.setup.conf ────────────────────────────────────────────────────────
if [[ -s "$WORK_DIR/setup.conf" ]]; then
    ohai "Restoring ~/.setup.conf"
    cp "$WORK_DIR/setup.conf" "$HOME/.setup.conf"
    chmod 600 "$HOME/.setup.conf"
    info "~/.setup.conf written"
fi

# ── Restore VS Code extensions ────────────────────────────────────────────────
if [[ -f "$WORK_DIR/vscode-extensions.txt" ]]; then
    _code_bin=""
    for _b in code code-insiders codium; do
        if command -v "$_b" &>/dev/null; then _code_bin="$_b"; break; fi
    done
    if [[ -n "$_code_bin" ]]; then
        ohai "Installing VS Code extensions"
        while IFS= read -r _ext || [[ -n "$_ext" ]]; do
            [[ -z "$_ext" ]] && continue
            "$_code_bin" --install-extension "$_ext" --force >/dev/null 2>&1 \
                && info "  $_ext" \
                || warn "  Failed to install: $_ext"
        done < "$WORK_DIR/vscode-extensions.txt"
    else
        warn "VS Code binary not found; skipping extension restore."
    fi
fi

# ── Download and run the installer ────────────────────────────────────────────
ohai "Fetching ubuntu-setup installer"
SETUP_URL="https://raw.githubusercontent.com/sunipkm/ubuntu-setup/master/setup.sh"
SETUP_SH="$WORK_DIR/setup.sh"
curl -fsSL "$SETUP_URL" -o "$SETUP_SH" && chmod +x "$SETUP_SH"

printf "\n"
ohai "Launching setup.sh — all settings from snapshot will be used automatically."
printf "(configure.sh will be skipped if ~/.setup.conf is already present)\n\n"
export SNAPSHOT_RESTORED=true
exec bash "$SETUP_SH"

exit 0
___END_OF_SNAPSHOT___
RESTORE_SCRIPT

# Append the base64 payload
cat "$PAYLOAD_B64" >> "$OUTPUT"

chmod +x "$OUTPUT"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
ohai "Done — snapshot written to: $OUTPUT  ($SIZE)"
printf "\nTo reproduce this environment on a fresh machine:\n"
printf "  bash %s\n\n" "$OUTPUT"
