#include <windows.h>
#include <WebView2.h>

extern "C" HRESULT memo_webview2_edit(ICoreWebView2Controller *controller, LPCWSTR parameters) {
  ICoreWebView2 *view = nullptr;
  auto result = controller->get_CoreWebView2(&view);
  if (FAILED(result)) return result;
  if (!view) return E_POINTER;

  // Send the command to this WebView. The caller only checks submission errors.
  result = view->CallDevToolsProtocolMethod(L"Input.dispatchKeyEvent", parameters, nullptr);
  view->Release();
  return result;
}
