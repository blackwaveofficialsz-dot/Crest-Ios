const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const protocol = require('../work/test-core/Protocol');

test('auth form: submit observes current input and busy state in all four steps', () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/AuthPage.ets'), 'utf8');
  assert.match(source, /\.enabled\(this\.canSubmit\(\)\)/);
  assert.match(source, /\.opacity\(this\.canSubmit\(\) \? 1 : \.5\)/);
  const method = source.slice(source.indexOf('  private canSubmit()'), source.indexOf('  @Builder private submit'));
  const compiled = ts.transpileModule(`class Form { ${method} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const form = vm.runInNewContext(compiled.outputText + ';new Form()', protocol);
  Object.assign(form, { busy: false, step: 'phone', phone: '', password: '', code: '', nextPassword: '' });
  for (const [step, field, invalid, valid] of [
    ['phone', 'phone', '123', '13800000000'],
    ['password', 'password', '', 'fixture-only'],
    ['code', 'code', '12345', '123456'],
    ['reset', 'nextPassword', 'short', 'fixture-only']
  ]) {
    form.step = step; form[field] = invalid;
    assert.equal(form.canSubmit(), false, `${step}: invalid`);
    form[field] = valid;
    assert.equal(form.canSubmit(), true, `${step}: valid`);
    form.busy = true;
    assert.equal(form.canSubmit(), false, `${step}: in flight`);
    form.busy = false;
    assert.equal(form.canSubmit(), true, `${step}: request completed`);
    form[field] = invalid;
    assert.equal(form.canSubmit(), false, `${step}: input cleared`);
  }
});

test('auth form: a pending SMS challenge resumes securely after a page restart without resending', async () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/AuthPage.ets'), 'utf8');
  const lifecycle = source.slice(source.indexOf('  async aboutToAppear()'), source.indexOf('  private async perform('));
  const request = source.slice(source.indexOf('  private async requestCode('), source.indexOf('  private async verify('));
  const compiled = ts.transpileModule(`class Form { ${lifecycle} ${request} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const values = new Map(); let secret = '', sends = 0;
  const prefs = { get: async (key, fallback) => values.get(key) ?? fallback, put: async (key, value) => values.set(key, value), flush: async () => {} };
  const context = { ...protocol, preferences: { getPreferences: async () => prefs }, getContext: () => ({}),
    http: { RequestMethod: { POST: 'POST' } }, AUTH: '/auth/', body: value => value,
    ApiError: class extends Error { constructor(status, message) { super(message); this.status = status; } }, setInterval: () => 1, clearInterval: () => {} };
  const Form = vm.runInNewContext(compiled.outputText + ';Form', context);
  function page() {
    const form = new Form();
    Object.assign(form, { alive: false, phone: '13800000000', step: 'phone', challenge: '', challengePhone: '', purpose: 'login',
      cooldown: 0, resendAt: 0, notice: '', code: '', store: undefined,
      challengeVault: { read: () => secret, write: value => { secret = value; }, clear: () => { secret = ''; } },
      session: { api: { call: async () => { sends++; return { challenge_id: 'fixture-challenge', resend_after: 60, message: '' }; } } },
      t: value => value });
    return form;
  }
  const first = page(); await first.aboutToAppear(); await first.requestCode('login');
  assert.equal(sends, 1); assert.ok(first.cooldown > 0);
  assert.equal(values.has('phone'), false); assert.equal(values.has('challenge'), false);
  const restored = page(); await restored.aboutToAppear();
  assert.equal(restored.challenge, 'fixture-challenge');
  await restored.requestCode('login');
  assert.equal(restored.step, 'code'); assert.equal(sends, 1);
  restored.phone = '13900000000';
  await assert.rejects(restored.requestCode('login'), /操作频繁/);
  assert.equal(sends, 1);
  first.aboutToDisappear(); restored.aboutToDisappear();
});

test('account dialogs: old completions and errors cannot show after a workspace change', async () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/HomePage.ets'), 'utf8');
  const methods = source.slice(source.indexOf('  private async perform('), source.indexOf('  private async finishAccount('));
  const compiled = ts.transpileModule(`class Page { ${methods} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  for (const joining of [true, false]) {
    for (const succeeds of [true, false]) {
      const page = vm.runInNewContext(compiled.outputText + ';new Page()', { errorText: error => error.message });
      let resolve, reject; const gate = new Promise((yes, no) => { resolve = yes; reject = no; });
      Object.assign(page, { busy: false, panel: joining ? 'join' : 'password', completion: '', completionMessage: '', session: {
        revision: 1, user: { has_password: true }, join: () => gate, changePassword: () => gate
      } });
      const pending = page.submitAccount(); page.session.revision++;
      if (succeeds) resolve('old completion'); else reject(new Error('old failure'));
      await pending; assert.equal(page.completion, ''); assert.equal(page.completionMessage, '');
    }
  }
});

function profileForm() {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ProfileEditor.ets'), 'utf8');
  const validation = source.slice(source.indexOf('  private setBusy('), source.indexOf('  private release('));
  const save = source.slice(source.indexOf('  private async saveName('), source.indexOf('  @Builder private content('));
  const compiled = ts.transpileModule(`class Profile { ${validation} ${save} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const form = vm.runInNewContext(compiled.outputText + ';new Profile()', { errorText: error => error.message });
  Object.assign(form, { alive: true, busy: false, error: '', nickname: 'Fixture', session: { revision: 1 }, onBusyChange: () => {}, onClose: () => {} });
  return form;
}

test('profile: save matches nickname limits and allows unchanged valid names', () => {
  const form = profileForm();
  for (const [name, allowed] of [['', false], ['   ', false], [' Fixture ', true], ['测'.repeat(30), true], ['测'.repeat(31), false], ['😀'.repeat(30), true]]) {
    form.nickname = name; assert.equal(form.canSave(), allowed);
  }
  form.busy = true; assert.equal(form.canSave(), false);
});

test('profile: save dismisses only after success; failures stay editable and stale completion cannot dismiss', async () => {
  for (const outcome of ['success', 'failure', 'stale', 'closed']) {
    const form = profileForm(); let resolve, reject, dismissals = 0; const busy = [];
    const pending = new Promise((yes, no) => { resolve = yes; reject = no; });
    form.session.setName = () => pending; form.onClose = () => dismissals++; form.onBusyChange = value => busy.push(value);
    const saving = form.saveName(); assert.equal(form.busy, true); assert.equal(dismissals, 0);
    if (outcome === 'stale') form.session.revision++;
    if (outcome === 'closed') form.alive = false;
    if (outcome === 'failure') reject(new Error('fixture failure')); else resolve();
    await saving;
    assert.equal(dismissals, outcome === 'success' ? 1 : 0); assert.equal(form.busy, false);
    assert.equal(form.error, outcome === 'failure' ? 'fixture failure' : '');
    assert.equal(busy[0], true);
  }
});

function sidebarPage() {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/HomePage.ets'), 'utf8');
  const methods = source.slice(source.indexOf('  private beginSidebarDrag('), source.indexOf('  @Builder private heading('));
  const compiled = ts.transpileModule(`class Page { ${methods} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  let animationCount = 0;
  const page = vm.runInNewContext(compiled.outputText + ';new Page()', { animateTo: (_, action) => { animationCount++; action(); }, Curve: { EaseOut: 'easeOut' } });
  Object.assign(page, { sidebar: false, sidebarDrag: 0, drawerWidth: 400, sheet: false, dialog: false, loads: 0, focusClears: 0,
    animationCount: () => animationCount, chat: { loadHistory: () => page.loads++ }, getUIContext: () => ({ getFocusController: () => ({ clearFocus: () => page.focusClears++ }) }) });
  return page;
}

test('dialogs: back dismisses only the top layer, returning account sheets to settings without writes', () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/HomePage.ets'), 'utf8');
  const method = source.slice(source.indexOf('  private back('), source.indexOf('  private canSend('));
  const compiled = ts.transpileModule(`class Page { ${method} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const page = vm.runInNewContext(compiled.outputText + ';new Page()');
  Object.assign(page, { busy: false, completion: '', dialog: true, sheet: true, panel: 'profile', sidebar: true, destination: 'analytics',
    openPanel: name => page.panel = name });
  assert.equal(page.back(), true); assert.equal(page.dialog, false); assert.equal(page.panel, 'profile');
  page.back(); assert.equal(page.panel, 'settings'); assert.equal(page.sheet, true);
  page.back(); assert.equal(page.sheet, false); assert.equal(page.sidebar, true);
  page.back(); assert.equal(page.sidebar, false); assert.equal(page.destination, 'analytics');
  page.back(); assert.equal(page.destination, 'chat'); assert.equal(page.back(), false);
  page.busy = true; page.dialog = true; page.back(); assert.equal(page.dialog, true);
  page.busy = false; page.completion = 'reauthenticate'; page.back(); assert.equal(page.dialog, true);
});
test('dialogs: native sheet back uses the page hierarchy; outside dismissal and busy guards are preserved', () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/HomePage.ets'), 'utf8');
  const binding = source.slice(source.indexOf('.bindSheet('));
  assert.ok(!binding.includes('shouldDismiss:'));
  const callback = binding.slice(binding.indexOf('onWillDismiss:') + 'onWillDismiss:'.length, binding.indexOf(',\n        onDisappear:'));
  const compiled = ts.transpileModule(`const dismiss = ${callback};`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const page = { busy: false, completion: '', sheet: true, backCalls: 0, back() { this.backCalls++; } };
  // Execute the actual native callback against one persistent page-like context.
  const context = vm.createContext({ ...page, DismissReason: { PRESS_BACK: 0 } });
  vm.runInContext(compiled.outputText, context);
  vm.runInContext('dismiss({ reason: 0 })', context);
  assert.equal(context.backCalls, 1); assert.equal(context.sheet, true);
  for (const reason of [1, 2, 3]) {
    context.sheet = true; vm.runInContext(`dismiss({ reason: ${reason} })`, context); assert.equal(context.sheet, false);
  }
  for (const guard of ['busy', 'completion']) {
    context[guard] = guard === 'busy' ? true : 'reauthenticate'; context.sheet = true;
    vm.runInContext('dismiss({ reason: 0 }); dismiss({ reason: 1 })', context);
    assert.equal(context.sheet, true); assert.equal(context.backCalls, 1);
    context[guard] = guard === 'busy' ? false : '';
  }
});
function drag(x, y = 0, start = 20, velocity = 0) {
  return { offsetX: x, offsetY: y, velocityX: velocity, fingerList: [{ globalX: start + x }] };
}

test('sidebar: only horizontal drags from the left 32 points open it; modal and vertical gestures are excluded', () => {
  for (const [event, modal] of [[drag(180, 0, 80), ''], [drag(180, 220), ''], [drag(180), 'sheet'], [drag(180), 'dialog']]) {
    const page = sidebarPage(); if (modal) page[modal] = true;
    page.beginSidebarDrag(event); page.finishSidebarDrag(event);
    assert.equal(page.sidebar, false); assert.equal(page.loads, 0); assert.equal(page.focusClears, 0);
  }
});

test('sidebar: threshold, fling, cancellation and reverse close follow the iOS interaction rules', () => {
  for (const [distance, speed, expected] of [[135, 0, false], [136, 0, true], [50, 800, true]]) {
    const page = sidebarPage(), event = drag(distance, 0, 20, speed);
    page.beginSidebarDrag(event); assert.equal(page.sidebarDrag, distance);
    page.finishSidebarDrag(event); assert.equal(page.sidebar, expected); assert.equal(page.sidebarDrag, 0);
    assert.equal(page.loads, expected ? 1 : 0); assert.equal(page.focusClears, 1);
  }
  const page = sidebarPage(); page.beginSidebarDrag(drag(200)); page.finishSidebarDrag();
  assert.equal(page.sidebar, false); assert.equal(page.sidebarDrag, 0);
  page.sidebar = true; page.beginSidebarDrag(drag(-160, 0, 300)); page.finishSidebarDrag(drag(-160, 0, 300));
  assert.equal(page.sidebar, false); assert.equal(page.loads, 0);
});

test('sidebar: progress is clamped to drawer width and cannot drag outward when open', () => {
  const page = sidebarPage(); page.beginSidebarDrag(drag(800)); assert.equal(page.sidebarDrag, 400);
  page.finishSidebarDrag(drag(800)); page.beginSidebarDrag(drag(40, 0, 100)); assert.equal(page.sidebarDrag, 0);
  page.moveSidebarDrag(drag(-800, 0, 100)); assert.equal(page.sidebarDrag, -400);
});

test('sidebar: reduced motion settles immediately without an animation', () => {
  const page = sidebarPage();
  page.reduceMotion = true;
  page.settleSidebar(true);
  assert.equal(page.sidebar, true); assert.equal(page.animationCount(), 0);
  page.reduceMotion = false;
  page.settleSidebar(false);
  assert.equal(page.sidebar, false); assert.equal(page.animationCount(), 1);
});
