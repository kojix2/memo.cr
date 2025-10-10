#!/usr/bin/env bash
set -euo pipefail

# Build for Windows (MinGW64) using MSYS2; set WV2_VER to override version
: "${WV2_VER:=1.0.1150.38}"

# Must run from repository root
([ -f shards.yml ] || [ -f shard.yml ]) || { echo "error: run at repo root" >&2; exit 1; }

# WebView2 headers (NuGet)
mkdir -p _wv2
curl -fL "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WV2_VER}" -o _wv2/webview2.nupkg
unzip -q _wv2/webview2.nupkg "build/native/include/*.h" -d _wv2 || { echo "error: unzip WebView2" >&2; exit 1; }
[ -f _wv2/build/native/include/WebView2.h ] || { echo "error: WebView2.h not found" >&2; exit 1; }

# Env for webview postinstall (needs headers)
export CXX="g++ -I$(pwd)/_wv2/build/native/include"
export CXXFLAGS="-DWEBVIEW_EDGE=1 -DWEBVIEW_BUILD_SHARED=1 -std=c++14"

# Dependencies
shards install --without-development

# Link directory for webview ext
LINKDIR="$(pwd)/lib/webview/ext"; command -v cygpath >/dev/null 2>&1 && LINKDIR="$(cygpath -m "$LINKDIR")"

# Build
shards build --release --no-debug --static -Dpreview_mt -Dexecution_context \
  --link-flags="-Wl,--subsystem,windows -L $LINKDIR -Wl,--start-group -lwebview -lstdc++ -Wl,--end-group -lole32 -lcomctl32 -loleaut32 -luuid -lgdi32 -lshlwapi -lversion"
