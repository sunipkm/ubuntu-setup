#!/bin/bash
SPWD=$(pwd)
USER=$(whoami)

if ! which git &> /dev/null; then
    sudo apt update && sudo apt install git git-lfs
fi

# update git name and email
GITEMAIL=`git config --global user.email`
if [ ! "$GITEMAIL" ]; then
    echo -n "Enter email for git: "
    input=
    while [[ $input = "" ]]; do
    read input
    done
    git config --global user.email "$input"
fi

GITUSER=`git config --global user.name`
if [ ! "$GITUSER" ]; then
    echo -n "Enter user name (in full) for git: "
    input=
    while [[ $input = "" ]]; do
    read input
    done
    git config --global user.name "$input"
fi

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

cd $WORK_DIR && git clone https://github.com/sunipkm/ubuntu-setup && cd ubuntu-setup
bash move_config.sh