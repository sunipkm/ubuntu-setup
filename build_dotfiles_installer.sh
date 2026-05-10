#!/bin/bash
# Build a release package for the project
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

tar -cvzf "$WORK_DIR/dotfiles.tar.gz" dotfiles dotfiles_debian
base64 < "$WORK_DIR/dotfiles.tar.gz" > "$WORK_DIR/dotfiles_payload.txt"
cat dotfiles_installer_base.sh $WORK_DIR/dotfiles_payload.txt > "$PDIR/dotfiles_installer.sh"