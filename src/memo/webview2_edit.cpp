#include <windows.h>
#include <WebView2.h>
#include <new>

namespace {
// The WebView2 SDK declares the IID but does not provide its definition
// when linking without WebView2Loader. Keep this usable with MinGW.
constexpr IID edit_completed_iid = {
    0x5c4889f0, 0x5ef6, 0x4c5a, {0x95, 0x2c, 0xd8, 0xf1, 0xb9, 0x2d, 0x05, 0x74}};

class EditCompleted final : public ICoreWebView2CallDevToolsProtocolMethodCompletedHandler {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, edit_completed_iid))
      return E_NOINTERFACE;
    *result = static_cast<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *>(this);
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    auto remaining = --refs_;
    if (remaining == 0) delete this;
    return remaining;
  }

  HRESULT STDMETHODCALLTYPE Invoke(HRESULT error, LPCWSTR) override {
    if (FAILED(error)) OutputDebugStringW(L"Memo: WebView2 editing command failed\n");
    return S_OK;
  }

 private:
  ULONG refs_ = 1;
};
}

extern "C" HRESULT memo_webview2_edit(ICoreWebView2Controller *controller, LPCWSTR parameters) {
  ICoreWebView2 *view = nullptr;
  auto result = controller->get_CoreWebView2(&view);
  if (FAILED(result)) return result;
  if (!view) return E_POINTER;

  auto *completed = new (std::nothrow) EditCompleted;
  if (completed) {
    // Trigger the renderer's editor command just as a key binding would.
    // This neither sends system-wide keystrokes nor grants clipboard access to JS.
    result = view->CallDevToolsProtocolMethod(L"Input.dispatchKeyEvent", parameters, completed);
    completed->Release();
  } else {
    result = E_OUTOFMEMORY;
  }
  view->Release();
  return result;
}
