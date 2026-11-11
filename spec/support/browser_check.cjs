// Optional real-browser checks. Requires Playwright and a compiled fixture server.
// NODE_PATH=/path/to/node_modules node spec/support/browser_check.cjs
const { chromium } = require('playwright');
const { DatabaseSync } = require('node:sqlite');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const readline = require('node:readline');

(async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'memo-browser-'));
  const artifacts = path.resolve('dist/gui-check');
  await fs.mkdir(artifacts, { recursive: true });
  const checks = [];
  const issues = [];
  let server, browser;
  let pending = [];
  const request = (requestPath, body = '') => new Promise((resolve, reject) => {
    pending.push({ resolve, reject });
    server.stdin.write(JSON.stringify({ path: requestPath, body }) + '\n');
  });
  const verify = (name, value) => {
    checks.push({ name, passed: !!value });
    if (!value) issues.push(name);
    console.log(`${value ? 'PASS' : 'FAIL'} ${name}`);
  };
  const start = async binary => {
    server = spawn(binary, [root], { env: { ...process.env }, stdio: ['pipe', 'pipe', 'pipe'] });
    let output = '';
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Fixture startup timed out: ' + output)), 15000);
      readline.createInterface({ input: server.stdout }).on('line', line => {
        const message = JSON.parse(line);
        if (message.ready) { clearTimeout(timer); resolve(); }
        else pending.shift().resolve(message);
      });
      server.stderr.on('data', data => { output += data; });
      server.once('exit', code => {
        clearTimeout(timer);
        const error = new Error(`Fixture exited ${code}: ${output}`);
        reject(error);
        for (const item of pending.splice(0)) item.reject(error);
      });
    });
  };
  const stop = async () => {
    if (!server || server.exitCode !== null) return;
    await new Promise(resolve => { server.once('exit', resolve); server.kill('SIGTERM'); });
  };
  try {
    // A version-1 settings file and the pre-CrystKit SQLite schema, created
    // from scratch. No user's files are read or copied into the fixture.
    const db = new DatabaseSync(path.join(root, 'memo.db'));
    db.exec(`CREATE TABLE notes (id integer primary key autoincrement, title text not null,
      body text not null, created_at text not null, updated_at text not null)`);
    db.prepare('INSERT INTO notes VALUES (?, ?, ?, ?, ?)').run(7, '以前のメモ（検証用）', '旧SQLiteの本文 日本語😀', '2026-01-13 10:00:00', '2026-01-13 10:00:00');
    const originalSchema = db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes'").get().sql;
    db.close();
    await fs.writeFile(path.join(root, 'settings.json'), JSON.stringify({ version: 1, ui: { editor_font_size_px: 20, sidebar_width_px: 320 } }));
    await start(path.resolve('bin/memo-browser-server'));
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1000, height: 700 } });
    // Fulfill every browser request through pipes. No local HTTP listener,
    // network connection, browser profile, or production IPC is exposed.
    await context.route('**/*', async route => {
      const response = await request(new URL(route.request().url()).pathname, route.request().postData() || '');
      await route.fulfill({ status: 200, contentType: response.content_type, body: response.body });
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    const ui = selector => page.locator(selector);
    const ready = () => ui('#new-note').waitFor({ state: 'visible' }).then(() => page.waitForFunction(() => !document.getElementById('new-note').disabled));
    const idle = () => page.waitForFunction(() => !document.getElementById('new-note').disabled);
    const saved = () => page.waitForFunction(() => document.getElementById('save-status').textContent === 'Saved');
    const screenshot = name => page.screenshot({ path: path.join(artifacts, name + '.png') });
    const width = () => ui('#notes-sidebar').evaluate(el => Math.round(el.getBoundingClientRect().width));
    const font = () => ui('#note-body').evaluate(el => parseFloat(getComputedStyle(el).fontSize));
    const menu = event => page.evaluate(event => window.__CRYSTKIT_IPC__._dispatchEvent(event, null), event);
    const confirm = value => request('/__confirm', String(value));
    await page.goto('http://memo.test/');
    await ready();
    verify('旧SQLiteのメモ・Unicodeを初回起動で復元', await ui('#note-body').inputValue() === '旧SQLiteの本文 日本語😀');
    verify('旧設定ファイルの文字サイズ・幅を復元', await font() === 20 && await width() === 320);
    await ui('#note-body').focus();
    await screenshot('01-editor-focused');
    verify('本文の入力中に茶色い枠が出ない', await ui('#note-body').evaluate(el => getComputedStyle(el).outlineStyle === 'none'));
    await ui('#delete-note').click();
    await idle();
    verify('最後のメモを削除すると空画面になる', await ui('#empty-state').isVisible() && await ui('.note-item').count() === 0);
    await screenshot('02-empty');
    await ui('#new-note').click();
    await idle();
    verify('新規作成後に本文へフォーカス', await ui('#note-body').evaluate(el => document.activeElement === el));
    await ui('#note-title').fill('<script>日記😀</script>');
    await ui('#note-body').fill('一日目の記録\n日本語・絵文字😀・記号 < > &');
    await saved();
    verify('自動保存で一覧へ反映しHTMLを文字列として表示', (await ui('.note-item').first().textContent()).includes('<script>日記😀</script>') && await ui('.note-item script').count() === 0);
    await ui('#note-body').fill('切り替え直前の編集');
    await ui('#new-note').click();
    await idle();
    await ui('.note-item').nth(1).click();
    await idle();
    verify('新規作成・メモ切り替え前に未保存内容を保存', await ui('#note-body').inputValue() === '切り替え直前の編集');
    await ui('#note-body').dispatchEvent('compositionstart');
    await ui('#new-note').click();
    verify('IME変換中の操作で入力を失わない', await ui('.note-item').count() === 2 && await ui('#message').isVisible());
    await ui('#note-body').dispatchEvent('compositionend');
    await ui('#save-note').click();
    await idle();
    await ui('#note-body').fill('Simulated failing save');
    await page.waitForFunction(() => !document.getElementById('message').hidden && document.getElementById('message').textContent.includes('Simulated database write failure'));
    verify('保存失敗で本文が残りエラーが表示される', await ui('#note-body').inputValue() === 'Simulated failing save');
    await ui('#note-body').fill('保存失敗から自動再保存で復帰');
    await saved();
    verify('自動再保存に成功したら古い保存エラーを消す', await ui('#message').isHidden());
    await screenshot('03-save-recovery');
    const search = ui('#search-notes');
    const searchableBody = '冒頭の文章'.repeat(20) + '\n検索用の本文 日本語😀 MixedCASE [100%]';
    await ui('#note-body').fill(searchableBody);
    await search.fill('本文 日本語😀');
    verify('プレビュー外の本文・日本語・絵文字を未保存でも検索', await ui('.note-item').count() === 1 && await ui('#note-count').textContent() === '1 of 2 notes');
    await search.fill('mixedcase');
    verify('本文の大文字小文字を区別せず検索', await ui('.note-item').count() === 1);
    await search.fill('[100%]');
    verify('検索の記号を文字として扱う', await ui('.note-item').count() === 1);
    await search.fill('<script>');
    verify('タイトルだけの一致も検索しHTMLを実行しない', await ui('.note-item').count() === 1 && await ui('.note-item script').count() === 0);
    await search.fill('存在しない検索語');
    verify('検索結果ゼロでも編集中の本文を保持', await ui('.note-item').count() === 0 && await ui('.list-empty').textContent() === 'No matching notes' && await ui('#note-body').inputValue() === searchableBody);
    await screenshot('03-search-empty');
    await search.fill('mixedcase');
    await ui('#note-body').fill('検索中に本文を変更');
    verify('編集中の内容から検索結果を更新', await ui('.note-item').count() === 0 && await ui('#editor').isVisible());
    await ui('#note-body').fill(searchableBody);
    await saved();
    verify('自動保存後も検索条件を維持', await search.inputValue() === 'mixedcase' && await ui('.note-item').count() === 1);
    await search.dispatchEvent('keydown', { key: 'Escape', isComposing: true });
    verify('IME変換中のEscapeで検索語を消さない', await search.inputValue() === 'mixedcase');
    await search.press('Escape');
    verify('Escapeで検索を解除し全件表示', await search.inputValue() === '' && await ui('.note-item').count() === 2 && await ui('#note-count').textContent() === '2 notes');
    await search.fill('   ');
    verify('空白だけの検索では全件表示', await ui('.note-item').count() === 2);
    await search.fill('mixedcase');
    await ui('#new-note').click();
    await idle();
    verify('検索中の新規作成で検索を解除し新規メモを表示', await search.inputValue() === '' && await ui('.note-item').count() === 3 && await ui('#note-body').inputValue() === '');
    await ui('#delete-note').click();
    await idle();
    await search.fill('mixedcase');
    await ui('.note-item').click();
    await idle();
    verify('検索結果を選択して本文を開ける', await ui('#note-body').inputValue() === searchableBody);
    await search.fill('');
    await ui('#note-body').fill('保存失敗から自動再保存で復帰');
    await saved();
    await ui('#open-settings').click();
    await idle();
    verify('設定画面に情報を表示', await ui('#settings-page').isVisible() && (await ui('#app-info').textContent()).includes('runtime_env'));
    await ui('#editor-font-size').fill('23');
    await ui('#font-form button').click();
    await page.waitForFunction(() => document.getElementById('font-status').textContent === 'Saved');
    verify('設定の変更をリアクティブに反映', await font() === 23);
    await ui('#editor-font-size').fill('24');
    verify('設定の未保存編集時にSaved表示を消す', await ui('#font-status').textContent() !== 'Saved');
    await ui('#editor-font-size').fill('9');
    await ui('#font-form button').click();
    verify('範囲外の文字サイズを保存しない', await font() === 23);
    await ui('#editor-font-size').fill('23');
    await ui('#export-notes').click();
    await page.waitForFunction(() => document.getElementById('export-status').textContent.startsWith('Saved to'));
    const exported = JSON.parse(await fs.readFile(path.join(root, 'export.json'), 'utf8'));
    verify('エクスポートに全件と編集内容を含む', exported.length === 2 && exported.some(n => n.body === '保存失敗から自動再保存で復帰'));
    await request('/__cancel_export', 'true');
    await ui('#export-notes').click();
    await page.waitForFunction(() => document.getElementById('export-status').textContent === 'Export cancelled');
    verify('エクスポートをキャンセルできる', await ui('#export-status').textContent() === 'Export cancelled');
    await screenshot('04-settings');
    await ui('#back-to-notes').click();
    const beforeDelete = await ui('#note-body').inputValue();
    await confirm(false);
    await ui('#delete-note').click();
    await idle();
    verify('削除キャンセルで選択・本文・件数を維持', await ui('#note-body').inputValue() === beforeDelete && await ui('.note-item').count() === 2);
    await confirm(true);
    await ui('#delete-note').click();
    await idle();
    verify('削除後に次のメモを選択', await ui('.note-item').count() === 1 && await ui('#editor').isVisible());
    const box = await ui('#sidebar-resizer').boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + 100);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 80, box.y + 100, { steps: 8 });
    await page.mouse.up();
    verify('実際のマウスドラッグでサイドバーの幅を変更', await width() === 400);
    await ui('#sidebar-resizer').focus();
    await page.keyboard.press('Home');
    verify('キーボード操作の最小幅', await width() === 150);
    await page.keyboard.press('End');
    verify('キーボード操作の最大幅', await width() === 600);
    await page.setViewportSize({ width: 500, height: 700 });
    await page.waitForFunction(() => document.getElementById('notes-sidebar').getBoundingClientRect().width <= 254);
    verify('狭いウィンドウに幅を収める', await width() <= 254);
    await screenshot('05-narrow');
    await page.setViewportSize({ width: 320, height: 700 });
    await page.waitForFunction(() => document.getElementById('notes-sidebar').getBoundingClientRect().width === 150);
    const controlsFit = await ui('.editor-actions button, #save-status').evaluateAll(buttons => buttons.every(button => {
      const rect = button.getBoundingClientRect();
      return rect.x >= document.querySelector('main').getBoundingClientRect().x && rect.right <= innerWidth;
    }));
    verify('320px幅でも保存・削除ボタンを画面内に収める', controlsFit);
    await screenshot('05-compact');
    await page.setViewportSize({ width: 1000, height: 700 });
    await page.waitForFunction(() => Math.round(document.getElementById('notes-sidebar').getBoundingClientRect().width) === 600);
    verify('ウィンドウを広げると指定幅を復元', await width() === 600);
    await page.keyboard.press('Home');
    for (let i = 0; i < 21; i++) await page.keyboard.press('ArrowRight');
    verify('幅を360pxへ調整', await width() === 360);
    await ui('#note-title').fill('再インストール後も残る日記');
    await ui('#note-body').fill('検証専用の本文 日本語😀');
    await menu('notes:save');
    await idle();
    await saved();
    await menu('app:close-requested');
    await idle();
    const diskSettings = JSON.parse(await fs.readFile(path.join(root, 'settings.json'), 'utf8'));
    verify('既存settings.jsonの形式のまま保存', diskSettings.version === 1 && diskSettings.ui.editor_font_size_px === 23 && diskSettings.ui.sidebar_width_px === 360);
    // Replace the executable, keeping ONLY the fixture data directory, then
    // reopen in a fresh process. No in-memory settings or DB connection survives.
    await stop();
    const replacement = path.join(root, 'reinstalled-memo');
    await fs.copyFile(path.resolve('bin/memo-browser-server'), replacement);
    await fs.chmod(replacement, 0o755);
    await start(replacement);
    await page.reload();
    await ready();
    verify('実行ファイル交換と別プロセス起動後にSQLiteを復元', await ui('#note-title').inputValue() === '再インストール後も残る日記' && await ui('#note-body').inputValue() === '検証専用の本文 日本語😀');
    verify('実行ファイル交換後に設定を復元', await width() === 360 && await font() === 23);
    await ui('#note-body').focus();
    await screenshot('06-reinstalled');
    const restoredDb = new DatabaseSync(path.join(root, 'memo.db'));
    verify('旧SQLiteテーブル定義を変更していない', restoredDb.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes'").get().sql === originalSchema);
    restoredDb.close();
    verify('ブラウザー内の未処理例外なし', pageErrors.length === 0);
    await fs.writeFile(path.join(artifacts, 'report.json'), JSON.stringify({ fixture: root, checks, pageErrors }, null, 2));
    console.log('Artifacts: ' + artifacts);
    assert.equal(issues.length, 0, 'UI issues: ' + issues.join('; '));
  } finally {
    await browser?.close();
    await stop();
    // Retain only synthetic fixtures for diagnosis; never touch user data.
    console.log('Synthetic fixture: ' + root);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
