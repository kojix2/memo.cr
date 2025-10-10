#!/usr/bin/env bash
set -euo pipefail

# Build for Windows (MinGW64) using MSYS2
# Requirements: MSYS2 MINGW64 with crystal, shards, gcc, curl, unzip
# Optional: set WV2_VER to pin Microsoft.Web.WebView2 headers version

WV2_VER="${WV2_VER:-1.0.1150.38}"

# Must run from repository root
if [ ! -f shards.yml ] && [ ! -f shard.yml ]; then
  echo "error: run from repository root (missing shards.yml/shard.yml)" >&2
  exit 1
fi

# Fetch WebView2 headers (NuGet)
mkdir -p _wv2
cd _wv2
curl -fL "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WV2_VER}" -o webview2.nupkg
mkdir -p build/native/include
unzip -q webview2.nupkg "build/native/include/*.h" -d . || {
  echo "error: failed to extract WebView2 headers" >&2
  exit 1
}
cd ..

# Install dependencies
shards install --without-development

# Prepare link directory for webview ext
LINKDIR="$(pwd)/lib/webview/ext"
if command -v cygpath >/dev/null 2>&1; then
  LINKDIR="$(cygpath -m "$LINKDIR")"
fi

# Compiler flags for webview (Edge)
export CXX="g++ -I$(pwd)/_wv2/build/native/include"
export CXXFLAGS="-DWEBVIEW_EDGE=1 -DWEBVIEW_BUILD_SHARED=1 -std=c++14"

# Build the Crystal executable
shards build --release --no-debug --static -Dpreview_mt -Dexecution_context \
  --link-flags="-Wl,--subsystem,windows -L $LINKDIR -Wl,--start-group -lwebview -lstdc++ -Wl,--end-group -lole32 -lcomctl32 -loleaut32 -luuid -lgdi32 -lshlwapi -lversion"

echo "build: finished"
