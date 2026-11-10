(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ipc = window.__CRYSTKIT_IPC__;
  const invoke = (name, payload) => ipc.invoke(name, payload);
  let notes;
  let busy = false;
  let loaded = false;
  let timer;
  let deleteTimer;
  let deleteArmed = false;
  let closing = false;
  let composing = false;
  let settingsOpen = false;
  const sidebar = $('notes-sidebar');
  const splitter = $('sidebar-resizer');
  let sidebarWidth = 280;
  let sidebarDrag = null;
  let sidebarSave = Promise.resolve();
  const editor = new MemoEditor(invoke, (text, error = false) => {
    $('save-status').textContent = text;
    if (error) showError(text);
  });

  function showError(error) {
    $('message').textContent = error.message || String(error);
    $('message').hidden = false;
  }
  function clearError() { $('message').hidden = true; }
  function maxSidebarWidth() {
    // Leave space for the splitter and at least 240px of editor content.
    return Math.max(150, Math.min(600, document.documentElement.clientWidth - 246));
  }
  function renderSidebarWidth() {
    const max = maxSidebarWidth();
    const width = Math.min(sidebarWidth, max);
    sidebar.style.setProperty('--sidebar-width', width + 'px');
    splitter.setAttribute('aria-valuemax', max);
    splitter.setAttribute('aria-valuenow', width);
  }
  function setSidebarWidth(width) {
    sidebarWidth = Math.round(Math.max(150, Math.min(width, maxSidebarWidth())));
    renderSidebarWidth();
  }
  function persistSidebarWidth() {
    const width = sidebarWidth;
    sidebarSave = sidebarSave.then(() => invoke('settings.save_sidebar_width', width)).catch(showError);
  }
  function finishSidebarResize(event) {
    if (!sidebarDrag || (event && event.pointerId !== sidebarDrag.pointerId)) return;
    const { pointerId } = sidebarDrag;
    sidebarDrag = null;
    document.body.classList.remove('resizing-sidebar');
    if (splitter.hasPointerCapture(pointerId)) splitter.releasePointerCapture(pointerId);
    persistSidebarWidth();
  }
  splitter.addEventListener('pointerdown', event => {
    if (!loaded || closing || sidebarDrag || event.button !== 0 || !event.isPrimary) return;
    event.preventDefault();
    splitter.setPointerCapture(event.pointerId);
    sidebarDrag = { pointerId: event.pointerId, x: event.clientX, width: sidebar.getBoundingClientRect().width };
    document.body.classList.add('resizing-sidebar');
  });
  splitter.addEventListener('pointermove', event => {
    if (!sidebarDrag || event.pointerId !== sidebarDrag.pointerId) return;
    setSidebarWidth(sidebarDrag.width + event.clientX - sidebarDrag.x);
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    splitter.addEventListener(type, finishSidebarResize);
  }
  splitter.addEventListener('keydown', event => {
    if (!loaded || closing || event.altKey || event.ctrlKey || event.metaKey) return;
    const width = sidebar.getBoundingClientRect().width;
    const next = { ArrowLeft: width - 10, ArrowRight: width + 10, Home: 150, End: maxSidebarWidth() }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    setSidebarWidth(next);
    persistSidebarWidth();
  });
  window.addEventListener('resize', renderSidebarWidth);
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
  function disarmDelete() {
    clearTimeout(deleteTimer);
    deleteArmed = false;
    $('delete-note').textContent = 'Delete';
    $('delete-note').classList.remove('armed');
  }
  function showNote(note) {
    editor.select(note);
    disarmDelete();
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
  $('delete-note').addEventListener('click', () => {
    if (!deleteArmed) {
      deleteArmed = true;
      $('delete-note').textContent = 'Really delete?';
      $('delete-note').classList.add('armed');
      deleteTimer = setTimeout(disarmDelete, 3000);
      return;
    }
    action(async () => {
      // Drain autosaves first so a late write can never resurrect a deleted note.
      await flush();
      const id = editor.note.id;
      showNote(await invoke('notes.delete', id));
    });
  });
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
      if (!Number.isInteger(size) || size < 10 || size > 32) throw new Error('Choose a font size from 10 to 32 px.');
      const saved = await invoke('settings.save', size);
      document.documentElement.style.setProperty('--editor-font-size', saved.editor_font_size_px + 'px');
      $('font-status').textContent = 'Saved';
    });
  });
  $('export-notes').addEventListener('click', () => action(async () => {
    await flush();
    const path = await invoke('notes.export');
    $('export-status').textContent = path ? 'Saved to ' + path : 'Export cancelled';
  }));
  document.addEventListener('keydown', event => {
    if (!(event.metaKey || event.ctrlKey) || event.altKey || event.isComposing) return;
    const key = event.key.toLowerCase();
    if (key === 's') { event.preventDefault(); action(flush); }
    if (key === 'n') { event.preventDefault(); if (!settingsOpen) $('new-note').click(); }
    if (key === 'q' || key === 'w') { event.preventDefault(); requestClose(); }
  });
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
      finishSidebarResize();
      await sidebarSave;
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
  (async () => {
    try {
      await invoke('app.ready');
      const [noteState, settings] = await Promise.all([ipc.state('notes'), invoke('settings.get')]);
      notes = noteState;
      notes.subscribe(renderList);
      sidebarWidth = settings.ui.sidebar_width_px;
      renderSidebarWidth();
      $('editor-font-size').value = settings.ui.editor_font_size_px;
      document.documentElement.style.setProperty('--editor-font-size', settings.ui.editor_font_size_px + 'px');
      loaded = true;
      showNote(notes.value[0] || null);
      updateButtons();
    } catch (error) { showError(error); }
  })();
})();
