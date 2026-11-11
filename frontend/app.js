(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ipc = window.__CRYSTKIT_IPC__;
  const invoke = (name, payload) => ipc.invoke(name, payload);
  let notes;
  let busy = false;
  let loaded = false;
  let timer;
  let closing = false;
  let composing = false;
  let settingsOpen = false;
  const sidebar = new MemoSidebar($('notes-sidebar'), $('sidebar-resizer'), {
    enabled: () => loaded && !closing,
    save: width => invoke('settings.save_sidebar_width', width),
    onError: showError
  });
  let lastSaveError;
  const editor = new MemoEditor(invoke, (text, error) => {
    $('save-status').textContent = text;
    if (error) {
      lastSaveError = error.message;
      showError(error);
    } else if (text === 'Saved' && lastSaveError) {
      if ($('message').textContent === lastSaveError) clearError();
      lastSaveError = null;
    }
  });

  function showError(error) {
    $('message').textContent = error.message || String(error);
    $('message').hidden = false;
  }
  function clearError() { $('message').hidden = true; }
  function updateButtons() {
    $('new-note').disabled = $('open-settings').disabled = busy || closing || !loaded;
    $('save-note').disabled = $('delete-note').disabled = busy || !editor.note;
    document.querySelectorAll('.note-item').forEach(button => { button.disabled = busy; });
    $('back-to-notes').disabled = busy;
    $('export-notes').disabled = busy;
    document.querySelector('#font-form button').disabled = busy;
    $('note-title').readOnly = $('note-body').readOnly = busy;
  }
  async function action(work) {
    if (busy || closing) return;
    if (composing) { showError('Finish typing before continuing.'); return; }
    busy = true;
    clearTimeout(timer);
    clearError();
    updateButtons();
    try { await work(); }
    catch (error) { showError(error); }
    finally { busy = false; updateButtons(); }
  }
  function renderList() {
    const scrollTop = $('notes-list').scrollTop;
    const fragment = document.createDocumentFragment();
    for (const note of notes.value) {
      const button = document.createElement('button');
      const active = editor.note?.id === note.id;
      button.className = 'note-item' + (active ? ' active' : '');
      button.setAttribute('aria-current', active ? 'true' : 'false');
      for (const [className, text] of [
        ['note-title', note.title.trim() || 'Untitled'],
        ['note-preview', Array.from(note.body).slice(0, 51).join('') || 'Empty note'],
        ['note-date', note.updated_at.split(' ')[0]]
      ]) {
        const span = document.createElement('span');
        span.className = className;
        span.textContent = text;
        button.appendChild(span);
      }
      button.disabled = busy;
      button.addEventListener('click', () => action(async () => {
        await flush();
        showNote(notes.value.find(item => item.id === note.id));
      }));
      fragment.appendChild(button);
    }
    if (!notes.value.length) {
      const empty = document.createElement('p');
      empty.className = 'list-empty';
      empty.textContent = 'No notes yet';
      fragment.appendChild(empty);
    }
    $('notes-list').replaceChildren(fragment);
    $('notes-list').scrollTop = scrollTop;
    $('note-count').textContent = `${notes.value.length} ${notes.value.length === 1 ? 'note' : 'notes'}`;
  }
  function showNote(note) {
    editor.select(note);
    $('empty-state').hidden = !!note;
    $('editor').hidden = !note;
    $('note-title').value = note?.title || '';
    $('note-body').value = note?.body || '';
    $('save-status').textContent = note ? 'Saved' : '';
    renderList();
  }
  async function flush() {
    if (composing) throw new Error('Finish typing before continuing.');
    await editor.flush();
  }
  function scheduleSave() {
    clearTimeout(timer);
    if (composing) return;
    timer = setTimeout(() => {
      editor.flush().catch(showError);
    }, 800);
  }
  for (const input of [$('note-title'), $('note-body')]) {
    input.addEventListener('input', () => {
      editor.edit($('note-title').value, $('note-body').value);
      scheduleSave();
    });
    input.addEventListener('compositionstart', () => { composing = true; clearTimeout(timer); });
    input.addEventListener('compositionend', () => { composing = false; scheduleSave(); });
  }
  $('new-note').addEventListener('click', () => action(async () => {
    await flush();
    const note = await invoke('notes.create');
    showNote(note);
    $('note-body').focus();
  }));
  $('save-note').addEventListener('click', () => action(flush));
  $('delete-note').addEventListener('click', () => action(async () => {
    await flush();
    const id = editor.note.id;
    const next = await invoke('notes.delete', id);
    if (!next || next.id !== id) showNote(next);
  }));
  $('open-settings').addEventListener('click', () => action(async () => {
    await flush();
    const info = await invoke('app.info');
    const fragment = document.createDocumentFragment();
    for (const [label, value] of [['Version', info.version], ['Database', info.db_path || `Configured by ${info.db_url_source}`], ['Notes', info.note_count], ['Source', info.repository_url]]) {
      const dt = document.createElement('dt'); dt.textContent = label;
      const dd = document.createElement('dd'); dd.textContent = value;
      fragment.append(dt, dd);
    }
    $('app-info').replaceChildren(fragment);
    settingsOpen = true;
    $('notes-page').hidden = true;
    $('settings-page').hidden = false;
  }));
  $('back-to-notes').addEventListener('click', () => {
    settingsOpen = false;
    $('settings-page').hidden = true;
    $('notes-page').hidden = false;
  });
  $('font-form').addEventListener('submit', event => {
    event.preventDefault();
    action(async () => {
      const size = Number($('editor-font-size').value);
      if (!$('editor-font-size').checkValidity()) throw new Error('Choose a font size from 10 to 32 px.');
      await invoke('settings.save', size);
      $('font-status').textContent = 'Saved';
    });
  });
  $('export-notes').addEventListener('click', () => action(async () => {
    await flush();
    const path = await invoke('notes.export');
    $('export-status').textContent = path ? 'Saved to ' + path : 'Export cancelled';
  }));
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && !composing) editor.flush().catch(showError);
  });
  async function requestClose() {
    if (closing) return;
    if (composing) { showError('Finish typing before closing.'); return; }
    closing = true;
    clearTimeout(timer);
    try {
      // Wait for an in-progress action before flushing the final buffer.
      while (busy) await new Promise(resolve => setTimeout(resolve, 20));
      busy = true;
      updateButtons();
      $('note-title').readOnly = $('note-body').readOnly = true;
      await sidebar.flush();
      await flush();
      await invoke('app.close');
    } catch (error) {
      showError(error);
    } finally {
      $('note-title').readOnly = $('note-body').readOnly = false;
      closing = false;
      busy = false;
      updateButtons();
    }
  }
  if (!ipc) {
    showError('The CrystKit bridge is unavailable. Launch Memo from the desktop executable.');
    return;
  }
  ipc.listen('app:close-requested', requestClose);
  ipc.listen('notes:new', () => { if (!settingsOpen) $('new-note').click(); });
  ipc.listen('notes:save', () => action(flush));
  ipc.listen('notes:export', () => $('export-notes').click());
  ipc.listen('settings:open', () => $('open-settings').click());
  let renderedFontSize;
  function renderSettings(settings) {
    const ui = settings.ui;
    // Width publications must not overwrite an unfinished font-size edit.
    if (renderedFontSize !== ui.editor_font_size_px) {
      $('editor-font-size').value = ui.editor_font_size_px;
      renderedFontSize = ui.editor_font_size_px;
    }
    $('editor-font-size').min = ui.min_editor_font_size_px;
    $('editor-font-size').max = ui.max_editor_font_size_px;
    document.documentElement.style.setProperty('--editor-font-size', ui.editor_font_size_px + 'px');
  }
  (async () => {
    try {
      await invoke('app.ready');
      const [noteState, settings] = await Promise.all([ipc.state('notes'), ipc.state('settings')]);
      notes = noteState;
      notes.subscribe(renderList);
      settings.subscribe(renderSettings);
      renderSettings(settings.value);
      sidebar.width = settings.value.ui.sidebar_width_px;
      sidebar.render();
      loaded = true;
      showNote(notes.value[0] || null);
      updateButtons();
    } catch (error) { showError(error); }
  })();
})();
