const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoSidebar } = require('../frontend/sidebar.js');

function fixture(save) {
  const win = new EventTarget();
  const doc = new EventTarget();
  doc.defaultView = win;
  doc.documentElement = { clientWidth: 1000 };
  const classes = new Set();
  doc.body = { classList: { add: name => classes.add(name), remove: name => classes.delete(name) } };
  let width = 280;
  const sidebar = {
    ownerDocument: doc,
    style: { setProperty: (_, value) => { width = parseFloat(value); } },
    getBoundingClientRect: () => ({ width })
  };
  const splitter = new EventTarget();
  splitter.getBoundingClientRect = () => ({ width: 6 });
  const attrs = {};
  splitter.setAttribute = (name, value) => { attrs[name] = value; };
  splitter.setPointerCapture = () => { throw new Error('Capture unavailable'); };
  splitter.hasPointerCapture = () => false;
  const writes = [];
  const errors = [];
  const controller = new MemoSidebar(sidebar, splitter, {
    enabled: () => true,
    save: async value => { writes.push(value); if (save) await save(value); },
    onError: error => errors.push(error)
  });
  const send = (target, type, props = {}) => {
    const event = new Event(type, { cancelable: true });
    Object.assign(event, { pointerId: 1, button: 0, buttons: 1, isPrimary: true, clientX: width, ...props });
    target.dispatchEvent(event);
  };
  return { win, doc, splitter, attrs, classes, controller, writes, errors, send, width: () => width };
}

test('capture rejection still allows dragging outside the handle and persists on release', async () => {
  const f = fixture();
  f.send(f.splitter, 'pointerdown', { clientX: 280 });
  f.send(f.doc, 'pointermove', { clientX: 400, pointerId: 2 });
  assert.equal(f.width(), 280);
  f.send(f.doc, 'pointermove', { clientX: 400 });
  assert.equal(f.width(), 400);
  f.send(f.doc, 'pointerup');
  await f.controller.flush();
  assert.deepEqual(f.writes, [400]);
  assert.equal(f.classes.size, 0);
  f.send(f.doc, 'pointermove', { clientX: 500 });
  assert.equal(f.width(), 400);
});

test('blur and cancellation end dragging once, so the next drag works', async () => {
  for (const end of ['blur', 'pointercancel', 'lostpointercapture']) {
    const f = fixture();
    f.send(f.splitter, 'pointerdown');
    f.send(f.doc, 'pointermove', { clientX: 350 });
    f.send(end === 'blur' ? f.win : f.doc, end);
    f.send(f.doc, 'pointerup');
    await f.controller.flush();
    assert.deepEqual(f.writes, [350]);
    assert.equal(f.classes.size, 0);
    f.send(f.splitter, 'pointerdown');
    f.send(f.doc, 'pointermove', { clientX: 360 });
    await f.controller.flush();
    assert.deepEqual(f.writes, [350, 360]);
  }
});

test('returning after a release outside the WebView does not leave dragging stuck', async () => {
  const f = fixture();
  f.send(f.splitter, 'pointerdown');
  f.send(f.doc, 'pointermove', { clientX: 350 });
  f.send(f.doc, 'pointermove', { clientX: 500, buttons: 0 });
  await f.controller.flush();
  assert.equal(f.width(), 350);
  assert.deepEqual(f.writes, [350]);
  assert.equal(f.classes.size, 0);
});

test('viewport clamping preserves the preferred width and keyboard limits', async () => {
  const f = fixture();
  f.controller.setWidth(600);
  f.doc.documentElement.clientWidth = 500;
  f.send(f.win, 'resize');
  assert.equal(f.width(), 254);
  assert.equal(f.attrs['aria-valuemax'], 254);
  f.doc.documentElement.clientWidth = 1000;
  f.send(f.win, 'resize');
  assert.equal(f.width(), 600);
  f.send(f.splitter, 'keydown', { key: 'Home' });
  assert.equal(f.width(), 150);
  f.send(f.splitter, 'keydown', { key: 'ArrowRight' });
  assert.equal(f.width(), 160);
  await f.controller.flush();
  assert.deepEqual(f.writes, [150, 160]);
});

test('failed persistence blocks close until a retry succeeds', async () => {
  let failing = true;
  const f = fixture(async () => { if (failing) throw new Error('Disk full'); });
  f.send(f.splitter, 'keydown', { key: 'ArrowRight' });
  await assert.rejects(f.controller.flush(), /Disk full/);
  assert.equal(f.errors.length, 1);
  failing = false;
  await f.controller.flush();
  assert.deepEqual(f.writes, [290, 290, 290]);
});

test('saves stay ordered when another resize happens during a write', async () => {
  let release;
  const f = fixture(() => new Promise(resolve => { release = resolve; }));
  f.send(f.splitter, 'keydown', { key: 'ArrowRight' });
  await new Promise(resolve => setImmediate(resolve));
  f.send(f.splitter, 'keydown', { key: 'ArrowRight' });
  assert.deepEqual(f.writes, [290]);
  release();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.writes, [290, 300]);
  release();
  await f.controller.flush();
});
