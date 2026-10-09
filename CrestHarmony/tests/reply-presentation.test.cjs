// Execute shipped component methods and platform bridges; native layout is checked on the simulator.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const { responseStatus } = require('../work/test-core/ResponseFormat');
const { localizedFormat } = require('../work/test-core/Localization');
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
const replySource = read('components/RichMessage.ets');

function reply(overrides = {}) {
  const methods = replySource.slice(replySource.indexOf('  private showFooter()'), replySource.indexOf('  private noticeColor('));
  const callbacks = [], delays = [], copied = [], shared = [];
  const compiled = ts.transpileModule(`class Reply { ${methods} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const instance = vm.runInNewContext(compiled.outputText + '; new Reply()', {
    responseStatus, copyText: async text => copied.push(text), shareText: async (_, text) => shared.push(text),
    getContext: () => ({}), clearTimeout: id => { callbacks[id] = undefined; },
    setTimeout: (callback, delay) => { callbacks.push(callback); delays.push(delay); return callbacks.length - 1; }, ...overrides
  });
  const notices = [];
  Object.assign(instance, { message: { content: '正文 **保留 Markdown**\n', status: 'ok', error: '', parts: [{ kind: 'notice', message: '卡片不重复追加' }] },
    streaming: false, alive: true, copied: false, copyTimer: -1, t: key => key, toast: text => notices.push(text) });
  return { instance, callbacks, delays, copied, shared, notices };
}

test('reply: footer requires finished nonempty text and hides for failures or cards-only replies', () => {
  const { instance: view } = reply();
  assert.equal(view.showFooter(), true);
  view.streaming = true; assert.equal(view.showFooter(), false);
  view.streaming = false; view.message.error = 'failed'; assert.equal(view.showFooter(), false);
  view.message.error = '';
  for (const content of ['', ' \n\t ']) { view.message.content = content; assert.equal(view.showFooter(), false); }
  view.message.content = '恢复'; assert.equal(view.showFooter(), true);
});

test('reply: status badge appears only after streaming and never duplicates a failure card', () => {
  const { instance: view } = reply();
  assert.equal(view.showStatus(), false);
  for (const status of ['partial', 'empty', 'unavailable', 'failed', 'unknown']) {
    view.message.status = status; assert.equal(view.showStatus(), true);
    view.streaming = true; assert.equal(view.showStatus(), false); view.streaming = false;
    view.message.error = 'failed'; assert.equal(view.showStatus(), false); view.message.error = '';
  }
});

test('reply: copy/share preserve exact iOS text without appending AGUI and copy resets after three seconds', async () => {
  const { instance: view, copied, shared, callbacks, delays } = reply();
  await view.copyReply(); await view.shareReply();
  assert.deepEqual(copied, [view.message.content]); assert.deepEqual(shared, copied);
  assert.equal(view.copied, true); assert.deepEqual(delays, [3000]);
  await view.copyReply(); assert.equal(callbacks[0], undefined);
  callbacks[1](); assert.equal(view.copied, false);
});

test('reply: clipboard/share errors show safe feedback; late clipboard completion cannot update a closed view', async () => {
  const failure = reply({ copyText: async () => { throw new Error('private platform detail'); }, shareText: async () => { throw new Error('private platform detail'); } });
  await failure.instance.copyReply(); await failure.instance.shareReply();
  assert.equal(failure.instance.copied, false);
  assert.deepEqual(failure.notices, ['复制失败', '未能打开分享面板']);
  let finish; const gate = new Promise(resolve => { finish = resolve; });
  const late = reply({ copyText: () => gate });
  const pending = late.instance.copyReply(); late.instance.alive = false; finish(); await pending;
  assert.equal(late.instance.copied, false); assert.deepEqual(late.notices, []); assert.deepEqual(late.delays, []);
});

function table(rows, total, locale = 'zh-Hans') {
  const source = read('components/ResponseTable.ets');
  const methods = source.slice(source.indexOf('  private visibleCount()'), source.indexOf('  @Builder private grid()'));
  const compiled = ts.transpileModule(`class Table { ${methods} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  let animations = 0;
  const instance = vm.runInNewContext(compiled.outputText + ';new Table()', { animateTo: (_, action) => { animations++; action(); } });
  Object.assign(instance, { rows, total, preview: 3, expanded: false, t: (key, args) => localizedFormat(key, locale, args), animationCount: () => animations });
  return instance;
}

test('table: preview, expand and collapse report only returned rows, never imply a fetch', () => {
  const view = table(Array.from({ length: 5 }, (_, i) => [String(i)]), 10);
  assert.equal(view.visibleCount(), 3); assert.equal(view.countLabel(), '当前展示 3 / 10 行');
  assert.equal(view.expansionLabel(), '展开已返回的 5 行');
  view.expanded = true; assert.equal(view.visibleCount(), 5); assert.equal(view.countLabel(), '当前展示 5 / 10 行');
  assert.equal(view.expansionLabel(), '收起');
  view.expanded = false; view.total = 2; assert.equal(view.countLabel(), '当前展示 3 / 5 行');
  assert.equal(view.expansionLabel(), '展开全部（5 行）');
});

test('table: explicit zero count is preserved, missing total is distinct, English labels use the catalog', () => {
  assert.equal(table([], 0).countLabel(), '当前展示 0 / 0 行');
  const english = table([['a'], ['b'], ['c'], ['d']], undefined, 'en');
  assert.equal(english.visibleCount(), 3);
  assert.equal(english.expansionLabel(), localizedFormat('展开全部（%lld 行）', 'en', ['4']));
  assert.match(read('components/ResponseTable.ets'), /if \(this\.total !== undefined\)/);
  assert.match(replySource, /total: part\.row_count,/);
});

test('table: reduced motion expands without an animation', () => {
  const view = table([['a'], ['b'], ['c'], ['d']], 4);
  view.reduceMotion = true; view.toggle();
  assert.equal(view.expanded, true); assert.equal(view.animationCount(), 0);
  view.reduceMotion = false; view.toggle();
  assert.equal(view.expanded, false); assert.equal(view.animationCount(), 1);
});

test('reply bindings: card kinds retain native styling and plain text; streaming hides parts/actions and selection', () => {
  assert.match(replySource, /if \(!this\.streaming\) \{ ForEach\(this\.message\.parts/);
  assert.match(replySource, /if \(!this\.streaming && this\.message\.actions\.length > 0\)/);
  assert.match(replySource, /copyOption\(this\.streaming \? CopyOptions\.None : CopyOptions\.InApp\)/);
  assert.match(replySource, /else if \(this\.message\.content\) \{ MarkdownView/);
  assert.ok(replySource.indexOf('if (this.showStatus())') < replySource.indexOf('if (this.message.error)'));
  const cards = replySource.slice(replySource.indexOf('  @Builder private part('), replySource.indexOf('  build() {', replySource.indexOf('export struct RichMessage')));
  assert.ok(!cards.includes('MarkdownView')); assert.ok(!cards.includes('InlineText'));
  for (const kind of ['table', 'notice', 'summary', 'insights', 'clarification']) assert.ok(cards.includes(`part.kind === '${kind}'`));
  assert.ok(!cards.includes('Palette.field')); assert.match(cards, /Column\(\{ space: 3 \}\)/);
  assert.match(replySource, /\.border\(\{ radius: 12, width: 1, color: '#33'/);
  const footer = replySource.slice(replySource.indexOf('if (this.showFooter())'));
  assert.equal((footer.match(/iconSize: 15/g) || []).length, 3);
  assert.match(read('components/Theme.ets'), /\.width\(44\)\.height\(44\)/);
  assert.equal((replySource.match(/enabled\(this\.canAct && !this\.streaming\)/g) || []).length, 3);
});

test('platform bridges: clipboard awaits completion and share receives text in the native controller', async () => {
  const source = read('services/MessageActions.ets');
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  let clipboardData, sharedData, shown;
  const modules = {
    '@kit.BasicServicesKit': { pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (type, text) => ({ type, text }), getSystemPasteboard: () => ({ setData: async data => { clipboardData = data; } }) } },
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { TEXT: 'general.plain-text' } } },
    '@kit.ShareKit': { systemShare: { SharedData: class { constructor(data) { sharedData = data; } }, ShareController: class { async show(context, options) { shown = { context, options }; } }, SelectionMode: { SINGLE: 1 }, SharePreviewMode: { DETAIL: 2 } } }
  };
  const exports = {}; vm.runInNewContext(compiled.outputText, { exports, require: name => modules[name] });
  const text = '**fixture**\n\nbody'; await exports.copyText(text); await exports.shareText('context', text);
  assert.equal(clipboardData.text, text); assert.equal(clipboardData.type, 'text/plain');
  assert.equal(sharedData.content, text); assert.equal(sharedData.utd, 'general.plain-text');
  assert.equal(shown.context, 'context'); assert.equal(shown.options.selectionMode, 1);
});

test('chat heading: reads observed title directly instead of a frozen Builder value parameter', () => {
  const source = read('pages/HomePage.ets');
  assert.match(source, /@Builder private heading\(\)/);
  assert.match(source, /Text\(this\.destination === 'chat' \? this\.chat\.title/);
  assert.equal((source.match(/this\.heading\(\)/g) || []).length, 3);
});
