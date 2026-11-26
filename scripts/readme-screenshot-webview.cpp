#define WIN32_LEAN_AND_MEAN
#include <windows.h>

// webview shows its top-level window before WebView2 starts. Only for the
// screenshot build, defer that show to Memo's app.ready handler. The WebView2
// child still has to be shown normally.
static BOOL show_webview_window(HWND window, int command) {
  return !GetParent(window) && command == SW_SHOW ? FALSE : ShowWindow(window, command);
}

#define ShowWindow show_webview_window
#include "webview.cc"
