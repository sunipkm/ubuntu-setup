#!/bin/bash
# Craft a release: build the artifact, tag, push, and publish to GitHub
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

# Check that gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is not installed or not in PATH"
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
    git -C "$PDIR" tag -a "$RELEASE_TAG" -m "Pre-release $RELEASE_TAG"
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

# Build the artifact using the existing build script
echo "Building artifact..."
"$PDIR/build_dotfiles_installer.sh" "$RELEASE_TAG"
if [[ $? -ne 0 ]]; then
    echo "Error: build_dotfiles_installer.sh failed"
    exit 1
fi

# Delete existing GitHub release if present, then recreate
echo "Creating GitHub release $RELEASE_TAG..."
if gh release view "$RELEASE_TAG" &>/dev/null; then
    echo "Release $RELEASE_TAG already exists on GitHub — deleting..."
    gh release delete "$RELEASE_TAG" --yes
fi
if [[ "$IS_PRERELEASE" == true ]]; then
    gh release create "$RELEASE_TAG" "$PDIR/dotfiles_installer.sh" \
        --title "$RELEASE_TAG" \
        --notes "Pre-release $RELEASE_TAG" \
        --prerelease
else
    gh release create "$RELEASE_TAG" "$PDIR/dotfiles_installer.sh" \
        --title "$RELEASE_TAG" \
        --notes "Release $RELEASE_TAG" \
        --verify-tag
fi

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create GitHub release for tag '$RELEASE_TAG'"
    exit 1
fi

echo "Release $RELEASE_TAG created successfully!"
