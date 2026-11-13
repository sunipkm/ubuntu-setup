#!/usr/bin/env bash
# Craft a release: create and push the tag. The Release workflow
# (.github/workflows/release.yml) builds dotfiles_installer.sh and publishes it.
# the directory of the script
PDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require a release tag argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <release-tag>"
    echo "  Release tag format: vX.Y.Z (stable) or vX.Y.Z-preN (pre-release)"
    exit 1
fi

RELEASE_TAG="$1"

# Validate tag format
if ! [[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-pre[0-9]+)?$ ]]; then
    echo "Error: Invalid release tag '$RELEASE_TAG'"
    echo "  Expected format: vX.Y.Z (stable) or vX.Y.Z-preN (pre-release)"
    exit 1
fi

# Determine if this is a pre-release
IS_PRERELEASE=false
if [[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-pre[0-9]+$ ]]; then
    IS_PRERELEASE=true
fi

# Fail if there are uncommitted changes
if ! git -C "$PDIR" diff --quiet || ! git -C "$PDIR" diff --cached --quiet; then
    echo "Error: There are uncommitted changes. Commit or stash them before crafting a release."
    exit 1
fi

# Delete existing local tag if present
if git -C "$PDIR" tag | grep -qx "$RELEASE_TAG"; then
    echo "Local tag $RELEASE_TAG already exists — deleting..."
    git -C "$PDIR" tag -d "$RELEASE_TAG"
fi

# Create git tag — signed for stable releases, annotated for pre-releases
if [[ "$IS_PRERELEASE" == false ]]; then
    echo "Creating signed tag $RELEASE_TAG..."
    git -C "$PDIR" tag -s "$RELEASE_TAG" -m "Release $RELEASE_TAG"
else
    echo "Creating pre-release tag $RELEASE_TAG..."
    git -C "$PDIR" -c tag.gpgSign=false tag -a "$RELEASE_TAG" -m "Pre-release $RELEASE_TAG"
fi

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create tag '$RELEASE_TAG'"
    exit 1
fi

# Push the tag to GitHub (force-push to overwrite if it exists remotely)
echo "Pushing tag $RELEASE_TAG to GitHub..."
git -C "$PDIR" push origin "$RELEASE_TAG" --force
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to push tag '$RELEASE_TAG' to GitHub"
    git -C "$PDIR" tag -d "$RELEASE_TAG"
    exit 1
fi

REPO_URL=$(git -C "$PDIR" remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
echo "Tag $RELEASE_TAG pushed. The Release workflow will build and publish it:"
echo "  $REPO_URL/actions/workflows/release.yml"
