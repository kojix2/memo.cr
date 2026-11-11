#!/bin/bash
set -euo pipefail

# Load configuration from .env
set -a
source .env
set +a
source scripts/linux-env.sh
VERSION="$(shards version .)"

DIST_DIR="dist"
ARCH="$(dpkg --print-architecture)"

echo "Building $APP_NAME v$VERSION..."
shards install --frozen
shards build --release $CRFLAGS

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Create temporary directory structure
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
chmod 755 "$TEMP_DIR"
mkdir -p "$TEMP_DIR/usr/bin"
mkdir -p "$TEMP_DIR/usr/share/applications"
mkdir -p "$TEMP_DIR/usr/share/icons/hicolor/256x256/apps"

# Copy binary
cp "bin/$APP_NAME" "$TEMP_DIR/usr/bin/"

# Generate desktop entry
cat > "$TEMP_DIR/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=$DESCRIPTION
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Categories=Utility;
StartupNotify=true
EOF

# Copy icon if it exists
if [ -f "resources/app_icon.png" ]; then
    cp "resources/app_icon.png" "$TEMP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
fi

# Derive versioned runtime dependencies from the executable, including libc/GMP.
# Keep the control stub outside the staged package contents.
METADATA_DIR="$TEMP_DIR/.metadata"
mkdir -p "$METADATA_DIR/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\nDescription: Memo\n' \
    "$APP_NAME" "$APP_NAME" > "$METADATA_DIR/debian/control"
BINARY_PATH="$TEMP_DIR/usr/bin/$APP_NAME"
dependencies="$(cd "$METADATA_DIR" && dpkg-shlibdeps -O -e "$BINARY_PATH")"
rm -rf "$METADATA_DIR"

mkdir -p "$TEMP_DIR/DEBIAN"
cat > "$TEMP_DIR/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: ${dependencies#shlibs:Depends=}
Homepage: $URL
License: $LICENSE
Description: $DESCRIPTION
EOF
dpkg-deb --root-owner-group --build "$TEMP_DIR" "$DIST_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"

echo "Created: $DIST_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"
