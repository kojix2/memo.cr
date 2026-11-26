#!/usr/bin/env bash
set -euo pipefail

# Build for Windows using MSYS2 UCRT64; optionally set WV2_VER to select an SDK.
if [[ "${MSYSTEM:-}" != "UCRT64" ]]; then
    echo "error: run this script in the MSYS2 UCRT64 environment" >&2
    exit 1
fi

# Must run from repository root
([ -f shards.yml ] || [ -f shard.yml ]) || { echo "error: run at repo root" >&2; exit 1; }

# WebView2 headers (NuGet)
mkdir -p _wv2
curl -fL "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2${WV2_VER:+/$WV2_VER}" -o _wv2/webview2.nupkg
unzip -qo _wv2/webview2.nupkg "build/native/include/*.h" -d _wv2 || { echo "error: unzip WebView2" >&2; exit 1; }
[ -f _wv2/build/native/include/WebView2.h ] || { echo "error: WebView2.h not found" >&2; exit 1; }

# Env for webview postinstall (needs headers)
export CXX="g++ -I$(pwd)/_wv2/build/native/include"
export CXXFLAGS="-DWEBVIEW_EDGE=1 -DWEBVIEW_BUILD_SHARED=1 -std=c++14"

# Dependencies
shards install --frozen --without-development

# Build
g++ -std=c++14 -I_wv2/build/native/include -c src/memo/webview2_edit.cpp -o _wv2/memo_webview2_edit.o
# Keep forward slashes in Crystal's linker flags: GCC treats backslashes as
# escapes when Crystal writes the flags to a response file.
webview_dir="$(cygpath -am lib/webview/ext)"
edit_object="$(cygpath -am _wv2/memo_webview2_edit.o)"
export MSYS2_ARG_CONV_EXCL='--link-flags='
link_flags="\"$edit_object\" -L\"$webview_dir\" -Wl,--start-group -lwebview -lstdc++ -Wl,--end-group -lole32 -lcomctl32 -loleaut32 -luuid -lgdi32 -lshlwapi -lversion"
if [[ "${MEMO_RUN_TESTS:-0}" == 1 ]]; then
    crystal tool format --check src spec
    crystal spec --link-flags="$link_flags"
fi
if [[ "${MEMO_TEST_CLIPBOARD:-0}" == 1 ]]; then
    crystal run spec/support/native_smoke.cr --link-flags="$link_flags"
fi
# Static libcrypto uses BCryptGenRandom. Keep bcrypt after OpenSSL because
# Crystal places custom link flags before its own library flags.
shards build --release --no-debug --static \
  --link-flags="-Wl,--subsystem,windows $link_flags -lssl -lcrypto -lbcrypt"
