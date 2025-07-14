#!/usr/bin/env bash
# Author: Jose Vicente Nunez
SCRIPT_END=$(grep --max-count 2 --line-number ___END_OF_SHELL_SCRIPT___ "$0"| cut -f 1 -d :| tail -1)|| exit 100
((SCRIPT_END+=1))

PLATFORM=$(uname -s)
if [[ "$PLATFORM" != "Linux" && "$PLATFORM" != "Darwin" ]]; then
    echo "Unsupported platform: $PLATFORM"
    exit 1
fi

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
    rm -rf "$WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

# extract the embedded file
tail --lines +"$SCRIPT_END" "$0"| base64 -d| tar --file - --extract --gzip --directory "$WORK_DIR"

# copy the files
if [[ -d "$WORK_DIR/dotfiles" ]]; then
    rsync --progress -r -u "$WORK_DIR/dotfiles/" "$HOME/"
else
    echo "No dotfiles directory found in the extracted files."
    exit 1
fi

if [[ "$PLATFORM" == "Linux" && -d "$WORK_DIR/dotfiles_debian" ]]; then
    rsync --progress -r -u "$WORK_DIR/dotfiles_debian/." "$HOME/"
elif [[ "$PLATFORM" == "Darwin" && -d "$WORK_DIR/dotfiles_macos" ]]; then
    rsync --progress -r -u "$WORK_DIR/dotfiles_macos/." "$HOME/"
else
    echo "No platform-specific dotfiles directory found."
fi

if ! [ -z "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc to .zshrc.bak"
    mv "$HOME/.zshrc" "$HOME/.zshrc.pre-dotfile-install"
fi

cp "$WORK_DIR/dotfiles/.zshrc" "$HOME/.zshrc"


exit 0
# Here's the end of the script followed by the embedded file
___END_OF_SHELL_SCRIPT___
