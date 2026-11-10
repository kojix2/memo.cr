# Source from the repository root before building on Linux.
# CrystKit's native desktop dependency asks for the older AppIndicator pkg-config
# name. Current Debian/Ubuntu provide the ABI-compatible Ayatana library instead.
# This alias lets pkg-config supply Ayatana's actual linker flags and SONAME.
if ! pkg-config --exists appindicator3-0.1 && pkg-config --exists ayatana-appindicator3-0.1; then
    mkdir -p .shards/pkgconfig
    cat > .shards/pkgconfig/appindicator3-0.1.pc <<'PC'
Name: AppIndicator compatibility
Description: Resolve AppIndicator through Ayatana AppIndicator
Version: 0.1
Requires: ayatana-appindicator3-0.1
PC
    export PKG_CONFIG_PATH="$PWD/.shards/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
