// Keep drag tracking on the document: pointer capture is optional in WebViews.
class MemoSidebar {
  constructor(sidebar, splitter, { enabled, save, onError, width = 280, min = 150, max = 600 }) {
    this.sidebar = sidebar;
    this.splitter = splitter;
    this.width = width;
    this.min = min;
    this.max = max;
    this.save = save;
    this.onError = onError;
    this.pending = Promise.resolve();
    this.drag = null;
    const doc = sidebar.ownerDocument;
    const win = doc.defaultView;
    this.doc = doc;
    this.win = win;

    splitter.addEventListener('pointerdown', event => {
      if (!enabled() || this.drag || event.button !== 0 || event.isPrimary === false) return;
      event.preventDefault();
      this.drag = { id: event.pointerId, x: event.clientX, width: sidebar.getBoundingClientRect().width };
      doc.body.classList.add('resizing-sidebar');
      // WKWebView can reject capture. Document listeners still track the drag.
      try { splitter.setPointerCapture(event.pointerId); } catch (_) {}
    });
    doc.addEventListener('pointermove', event => {
      if (!this.drag || event.pointerId !== this.drag.id) return;
      // A release outside an uncaptured WebView may never deliver pointerup.
      if (event.buttons === 0) { this.finish(); return; }
      this.setWidth(this.drag.width + event.clientX - this.drag.x);
    });
    for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
      doc.addEventListener(type, event => {
        if (this.drag && event.pointerId === this.drag.id) this.finish();
      });
    }
    win.addEventListener('blur', () => this.finish());
    win.addEventListener('resize', () => this.render());
    splitter.addEventListener('keydown', event => {
      if (!enabled() || event.altKey || event.ctrlKey || event.metaKey) return;
      const current = sidebar.getBoundingClientRect().width;
      const next = { ArrowLeft: current - 10, ArrowRight: current + 10, Home: this.min, End: this.limit }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      this.setWidth(next);
      this.persist();
    });
    this.render();
  }

  get limit() { return Math.max(this.min, Math.min(this.max, this.doc.documentElement.clientWidth - this.splitter.getBoundingClientRect().width - 240)); }

  render() {
    const width = Math.min(this.width, this.limit);
    this.sidebar.style.setProperty('--sidebar-width', width + 'px');
    this.splitter.setAttribute('aria-valuemin', this.min);
    this.splitter.setAttribute('aria-valuemax', this.limit);
    this.splitter.setAttribute('aria-valuenow', width);
  }

  setWidth(width) {
    this.width = Math.round(Math.max(this.min, Math.min(width, this.limit)));
    this.render();
  }

  persist() {
    const width = this.width;
    this.pending = this.pending.catch(() => {}).then(() => this.save(width));
    // Report failures immediately, while keeping pending rejected for close().
    this.pending.catch(this.onError);
  }

  finish() {
    if (!this.drag) return;
    const { id } = this.drag;
    this.drag = null;
    this.doc.body.classList.remove('resizing-sidebar');
    try {
      if (this.splitter.hasPointerCapture(id)) this.splitter.releasePointerCapture(id);
    } catch (_) {}
    this.persist();
  }

  async flush() {
    this.finish();
    try { await this.pending; }
    catch (_) {
      // Retry the current width; never allow a failed write to silently close.
      this.pending = Promise.resolve().then(() => this.save(this.width));
      await this.pending;
    }
  }
}

if (typeof module !== 'undefined' && module.exports) module.exports = { MemoSidebar };
