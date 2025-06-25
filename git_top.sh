#!/bin/bash

ROOT=$(
    git rev-parse --show-superproject-working-tree --show-toplevel 2>/dev/null | head -1;
    exit ${PIPESTATUS[0]}
)
RETCODE=$?
if [[ $RETCODE -ne 0 ]]; then
    echo "Not in a git repository or unable to determine the root directory."
    exit $RETCODE
fi

RELROOT=${ROOT##$HOME/}

if [[ "$ROOT" == "$RELROOT" ]]; then
    echo "$ROOT is not a subdirectory of $HOME, skipping."
    exit 1
fi

echo $RELROOT
