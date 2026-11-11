#!/bin/bash
set -euo pipefail

# Load configuration from .env
set -a
source .env
set +a
source scripts/linux-env.sh
VERSION="$(shards version .)"

DIST_DIR="dist"
MANIFEST="com.github.kojix2.memo.yml"
APP_ID=$(grep "^app-id:" "$MANIFEST" | awk '{print $2}')
CRFLAGS="${CRFLAGS:-}"

echo "Building $APP_NAME v$VERSION for Flatpak..."
shards install --frozen
shards build --release $CRFLAGS

if [ ! -f "bin/$APP_NAME" ]; then
    echo "Error: bin/$APP_NAME not found after build"
    exit 1
fi

mkdir -p "$DIST_DIR"

if ! command -v flatpak &> /dev/null; then
    echo "Error: flatpak is not installed"
    echo "Install with: sudo pacman -S flatpak (Arch/Manjaro)"
    echo "           or sudo apt install flatpak (Debian/Ubuntu)"
    exit 1
fi

if ! command -v flatpak-builder &> /dev/null; then
    echo "Error: flatpak-builder is not installed"
    echo "Install with: sudo pacman -S flatpak-builder (Arch/Manjaro)"
    echo "           or sudo apt install flatpak-builder (Debian/Ubuntu)"
    exit 1
fi

RUNTIME_VERSION=$(grep "runtime-version:" "$MANIFEST" | sed "s/.*'\(.*\)'.*/\1/")
if [ -z "$APP_ID" ] || [ -z "$RUNTIME_VERSION" ]; then
    echo "Error: failed to read app-id or runtime-version from $MANIFEST"
    exit 1
fi

if ! flatpak remotes | awk '{print $1}' | grep -q "^flathub$"; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

flatpak-builder --install-deps-from=flathub --force-clean --repo=repo build-dir "$MANIFEST"
bash scripts/check-flatpak-runtime.sh build-dir
flatpak build-bundle repo "$DIST_DIR/${APP_NAME}_${VERSION}.flatpak" "$APP_ID"

echo "Created: $DIST_DIR/${APP_NAME}_${VERSION}.flatpak"
