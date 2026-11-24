/* A single save queue owns the editor buffer. Edits made while an IPC save
 * is in flight remain dirty and are persisted before flush() resolves. */
class MemoEditor {
  constructor(invoke) {
    this.invoke = invoke;
    this.note = null;
    this.revision = 0;
    this.savedRevision = 0;
    this.pending = null;
  }

  get dirty() { return this.revision !== this.savedRevision; }

  select(note) {
    if (this.dirty || this.pending) throw new Error('Save the current note first.');
    this.note = note ? { ...note } : null;
    this.revision = this.savedRevision = 0;
  }

  edit(title, body) {
    if (!this.note) return;
    this.note = { ...this.note, title, body };
    this.revision++;
  }

  flush() {
    if (this.pending) return this.pending;
    if (!this.dirty) return Promise.resolve();
    this.pending = this.drain().finally(() => { this.pending = null; });
    return this.pending;
  }

  async drain() {
    while (this.dirty) {
      const revision = this.revision;
      const { id, title, body } = this.note;
      await this.invoke('notes.save', { id, title, body });
      this.savedRevision = revision;
    }
  }
}

if (typeof module !== 'undefined' && module.exports) module.exports = { MemoEditor };
