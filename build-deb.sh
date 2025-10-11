#!/bin/bash
set -e

# Load configuration from .env
set -a
source .env
set +a

DIST_DIR="dist"

echo "Building $APP_NAME v$VERSION..."
shards build --release $CRFLAGS

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Create temporary directory structure
TEMP_DIR=$(mktemp -d)
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

# Create deb package
fpm -s dir -t deb \
    --name "$APP_NAME" \
    --version "$VERSION" \
    --description "$DESCRIPTION" \
    --maintainer "$MAINTAINER" \
    --license "$LICENSE" \
    --url "$URL" \
    --deb-no-default-config-files \
    --depends "libwebkit2gtk-4.1-0" \
    --depends "libgtk-3-0" \
    --depends "libglib2.0-0" \
    --depends "libsqlite3-0" \
    --depends "libssl3" \
    --depends "libstdc++6" \
    --package "$DIST_DIR/${APP_NAME}_${VERSION}_amd64.deb" \
    -C "$TEMP_DIR" \
    .

rm -rf "$TEMP_DIR"

echo "Created: $DIST_DIR/${APP_NAME}_${VERSION}_amd64.deb"
