const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoEditor } = require('../frontend/editor.js');

const note = { id: 1, title: 'first', body: '', created_at: 'old', updated_at: 'old' };
const tick = () => new Promise(resolve => setImmediate(resolve));

test('edits during a save are drained before navigation or close can continue', async () => {
  const writes = [];
  let release;
  const editor = new MemoEditor(async (_, payload) => {
    writes.push(payload);
    await new Promise(resolve => { release = resolve; });
    return { ...payload, updated_at: 'now' };
  });
  editor.select(note);
  editor.edit('first edit', '日本語');
  const pending = editor.flush();
  assert.equal(editor.flush(), pending);
  editor.edit('second edit', '日本語 😀');
  release();
  await tick();
  assert.equal(writes.length, 2);
  assert.equal(writes[1].body, '日本語 😀');
  assert.equal(editor.dirty, true);
  release();
  await pending;
  assert.equal(editor.dirty, false);
  editor.select({ ...note, id: 2 });
});

test('a rejected save preserves the buffer and blocks switching until a retry succeeds', async () => {
  let failed = true;
  const editor = new MemoEditor(async (_, payload) => {
    if (failed) throw new Error('database is locked');
    return payload;
  });
  editor.select(note);
  editor.edit('unsaved', 'keep this');
  await assert.rejects(editor.flush(), /database is locked/);
  assert.equal(editor.dirty, true);
  assert.equal(editor.note.body, 'keep this');
  assert.throws(() => editor.select({ ...note, id: 2 }), /Save the current note/);
  failed = false;
  await editor.flush();
  assert.equal(editor.dirty, false);
  editor.select({ ...note, id: 2 });
});

test('a clean buffer never writes and a later edit is saved against the selected id', async () => {
  const writes = [];
  const editor = new MemoEditor(async (_, payload) => { writes.push(payload); return payload; });
  editor.select(note);
  await editor.flush();
  assert.equal(writes.length, 0);
  editor.select({ ...note, id: 2 });
  editor.edit('<script>', 'quotes & 😀');
  await editor.flush();
  assert.deepEqual(writes, [{ id: 2, title: '<script>', body: 'quotes & 😀' }]);
});
