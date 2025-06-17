#!/bin/bash -i
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

SPWD=$(pwd)
USER=$(whoami)

MACOS=$false
DEBIAN=$false

PLATFORM=$(uname -s)
if [[ "$PLATFORM" == "Linux" ]]; then
    echo "Detected Linux platform"
    if [[ -f /etc/debian_version ]]; then
        echo "Detected Debian-based system"
        DEBIAN=$true
        sudo apt-get update &>/dev/null && sudo apt-get install git git-lfs -y &>/dev/null
    else
        echo "This script is intended for Debian-based systems only."
        exit 1
    fi
elif [[ "$PLATFORM" == "Darwin" ]]; then
    echo "Detected macOS platform"
    MACOS=$true
    # Install xcode-select command line tools if not already installed
    if ! xcode-select -p &>/dev/null; then
        echo "Installing Xcode command line tools..."
        xcode-select --install
        # Wait for the installation to complete
        until $(xcode-select --print-path &>/dev/null); do
            sleep 5
        done
    fi
    # Install Homebrew if not already installed
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh --output install.sh
        INTERACTIVE=1
        source ./install.sh
    fi
else
    echo "This script is intended for Debian Linux and macOS platforms only."
    exit 1
fi

# Get git email
echo "Enter your git email: "
GITEMAIL=$(cat)
# Get git username
echo "Enter your git username: "
GITUSER=$(cat)
# Set git email and username globally
git config --global user.email "$GITEMAIL"
git config --global user.name "$GITUSER"

# Set git branch name to master
git config --global init.defaultBranch master

cd $WORK_DIR && git clone https://github.com/sunipkm/ubuntu-setup
cd ubuntu-setup

if [[ "$MACOS" == true ]]; then
    echo "Running macOS setup..."
    source ./macos_setup.sh
elif [[ "$DEBIAN" == true ]]; then
    echo "Running Debian setup..."
    source ./debian_setup.sh
fi
