#!/bin/bash
set -e

# Load configuration from .env
set -a
source .env
set +a

DIST_DIR="dist"

RPM_RELEASE="${RPM_RELEASE:-1}"
ARCH="${RPM_ARCH:-$(uname -m)}"

# RPM dependency defaults (switch by distro). Override with RPM_DEPENDS="pkg1 pkg2 ..." in .env if needed.
DEFAULT_DEPENDS_FEDORA="webkit2gtk4.1 gtk3 glib2 sqlite-libs openssl-libs libstdc++"
DEFAULT_DEPENDS_SUSE="libwebkit2gtk-4_1-0 libgtk-3-0 libglib-2_0-0 libsqlite3-0 libopenssl3 libstdc++6"

if [ -z "${RPM_DEPENDS:-}" ]; then
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    fi

    if [[ "${ID:-}" == "opensuse-tumbleweed" || "${ID:-}" == "opensuse-leap" || "${ID_LIKE:-}" == *"suse"* ]]; then
        RPM_DEPENDS="$DEFAULT_DEPENDS_SUSE"
    else
        RPM_DEPENDS="$DEFAULT_DEPENDS_FEDORA"
    fi
fi

IFS=' ' read -r -a DEPENDS <<< "$RPM_DEPENDS"

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

FPM_ARGS=(
    -s dir -t rpm
    --name "$APP_NAME"
    --version "$VERSION"
    --iteration "$RPM_RELEASE"
    --description "$DESCRIPTION"
    --maintainer "$MAINTAINER"
    --license "$LICENSE"
    --url "$URL"
    --architecture "$ARCH"
    --package "$DIST_DIR/${APP_NAME}-${VERSION}-${RPM_RELEASE}.${ARCH}.rpm"
)

for dep in "${DEPENDS[@]}"; do
    FPM_ARGS+=(--depends "$dep")
done

# Create rpm package
fpm "${FPM_ARGS[@]}" \
    -C "$TEMP_DIR" \
    .

rm -rf "$TEMP_DIR"

echo "Created: $DIST_DIR/${APP_NAME}-${VERSION}-${RPM_RELEASE}.${ARCH}.rpm"
