// Native bridges are replaced only in this test process; production uses HarmonyOS kits.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
class ApiError extends Error { constructor(status, message) { super(message); this.status = status; } }
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function fixture(overrides = {}) { return { token: 'test-access', refresh_token: 'test-refresh', user_id: 'test-user', username: '测试用户', has_password: true, workspace_type: 'tenant', active_workspace_id: 'w1', role: 'member', ...overrides }; }
function setup(saved = '') {
  let stored = saved, sequence = 0;
  const faults = { read: false, write: false, clear: false, preferences: false };
  const remembered = new Map();
  let blocked = false;
  const settings = {
    sessionRestoreBlocked() { return blocked; },
    async setSessionRestoreBlocked(value) { if (faults.preferences) throw new Error('preferences unavailable'); blocked = value; },
    lastWorkspace(userId) { return remembered.get(userId) || ''; },
    async rememberWorkspace(userId, workspaceId) { remembered.set(userId, workspaceId); }
  };
  class TokenStore {
    read() { if (faults.read) throw new Error('vault read failed'); return stored; }
    write(value) { if (faults.write) throw new Error('vault write failed'); stored = value; }
    clear() { if (faults.clear) throw new Error('vault clear failed'); stored = ''; }
  }
  class Api { async call() { throw new Error('Unexpected network call'); } }
  class RunRequest { thread = ''; run = ''; messageId = ''; text = ''; cursor = ''; }
  class StreamControl { cancelled = false; cancel() { this.cancelled = true; } }
  const apiExports = { Api, ApiError, RunRequest, StreamControl, AUTH: '/api/v1/auth/', body: JSON.stringify, errorText: error => error.message };
  let Session;
  const load = file => {
    const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
    const compiled = ts.transpileModule(source, { fileName: file + '.ts', compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, experimentalDecorators: true } });
    const module = { exports: {} };
    const localRequire = name => {
      if (name === '@kit.NetworkKit') return { http: { RequestMethod: { GET: 'GET', POST: 'POST', PATCH: 'PATCH', DELETE: 'DELETE' } } };
      if (name === '@kit.ImageKit') return { image: {} };
      if (name === '@kit.ArkTS') return { util: {
        generateRandomUUID: () => `id-${++sequence}`,
        Base64Helper: class { decodeSync(value) { return Buffer.from(value, 'base64'); } },
        TextDecoder: { create: () => ({ decodeToString: bytes => Buffer.from(bytes).toString('utf8') }) }
      } };
      if (name.endsWith('/Api') || name === './Api') return apiExports;
      if (name.endsWith('/TokenStore')) return { TokenStore };
      if (name.endsWith('/Settings')) return { settings };
      if (name.endsWith('/Session')) return { Session };
      if (name.endsWith('/Models')) return require('../work/test-core/Models');
      if (name.endsWith('/Protocol')) return require('../work/test-core/Protocol');
      throw new Error(`Unexpected import ${name}`);
    };
    vm.runInNewContext(compiled.outputText, { exports: module.exports, module, require: localRequire, Observed: value => value, Error, Promise, Date, setTimeout, clearTimeout, encodeURIComponent }, { filename: file });
    return module.exports;
  };
  Session = load('services/Session.ets').Session;
  const ChatStore = load('state/ChatStore.ets').ChatStore;
  const session = new Session();
  const account = (method, endpoint) => {
    if (endpoint.endsWith('/workspaces')) return { items: [], active_workspace_id: 'w1' };
    if (endpoint.endsWith('/profile')) return { username: '测试用户', display_name: '昵称', has_avatar: false };
    throw new Error(`Unexpected endpoint ${method} ${endpoint}`);
  };
  return { session, ChatStore, account, faults, remembered, stored: () => stored, blocked: () => blocked, restart: () => new Session() };
}
async function login(env) {
  env.session.api.call = async (method, endpoint) => endpoint.endsWith('/login') ? fixture() : env.account(method, endpoint);
  await env.session.signIn('login', '{}');
}
test('session: no stored credential goes directly to signed-out', async () => {
  const env = setup(); await env.session.restore(); assert.equal(env.session.state, 'signedOut');
});
test('session: network restore error keeps refresh credential for retry', async () => {
  const env = setup('saved-test-refresh'); env.session.api.call = async () => { throw new ApiError(503, 'unavailable'); };
  await env.session.restore(); assert.equal(env.session.state, 'restoreError'); assert.equal(env.stored(), 'saved-test-refresh');
});
test('session: unauthorized restore clears secure credentials', async () => {
  const env = setup('saved-test-refresh'); env.session.api.call = async () => { throw new ApiError(401, 'expired'); };
  await env.session.restore(); assert.equal(env.session.state, 'signedOut'); assert.equal(env.stored(), '');
});
test('session: profile failure does not invalidate successful login', async () => {
  const env = setup(); env.session.api.call = async (_method, endpoint) => {
    if (endpoint.endsWith('/login')) return fixture(); throw new ApiError(503, 'account unavailable');
  };
  await env.session.signIn('login', '{}'); assert.equal(env.session.state, 'signedIn'); assert.equal(env.stored(), 'test-refresh'); assert.ok(env.session.workspaceError);
});
test('session: simultaneous 401 requests share one refresh and retry', async () => {
  const env = setup(); await login(env); let refreshes = 0;
  const gate = deferred(); env.session.api.call = async () => { refreshes++; await gate.promise; return fixture({ token: 'new-test-access' }); };
  const operation = async token => { if (token === 'test-access') throw new ApiError(401, 'expired'); return token; };
  const first = env.session.authenticated(operation), second = env.session.authenticated(operation);
  await new Promise(resolve => setImmediate(resolve)); gate.resolve();
  assert.equal(await first, 'new-test-access'); assert.equal(await second, 'new-test-access'); assert.equal(refreshes, 1);
});
test('session: second 401 after refresh signs out', async () => {
  const env = setup(); await login(env); env.session.api.call = async () => fixture({ token: 'new-test-access' });
  await assert.rejects(() => env.session.authenticated(async () => { throw new ApiError(401, 'expired'); }));
  assert.equal(env.session.state, 'signedOut'); assert.equal(env.stored(), '');
});
test('session: non-401 error never triggers token refresh', async () => {
  const env = setup(); await login(env); let calls = 0; env.session.api.call = async () => { calls++; };
  await assert.rejects(() => env.session.authenticated(async () => { throw new ApiError(500, 'failed'); }));
  assert.equal(calls, 0); assert.equal(env.session.state, 'signedIn');
});
test('session: logout clears state even when backend unavailable', async () => {
  const env = setup(); await login(env); env.session.api.call = async () => { throw new Error('offline'); };
  await env.session.signOut(); assert.equal(env.session.state, 'signedOut'); assert.equal(env.stored(), '');
});
test('session: late refresh must not restore a logged-out account', async () => {
  const env = setup(); await login(env); const gate = deferred();
  env.session.api.call = async (_method, endpoint) => endpoint.endsWith('/refresh') ? gate.promise : {};
  const operation = env.session.authenticated(async () => { throw new ApiError(401, 'expired'); });
  const rejected = assert.rejects(operation);
  await new Promise(resolve => setImmediate(resolve)); await env.session.signOut(); gate.resolve(fixture()); await rejected;
  assert.equal(env.session.state, 'signedOut'); assert.equal(env.stored(), '');
});
test('profile: nickname trimmed and empty/oversized values rejected locally', async () => {
  const env = setup(); await login(env); let sent = '';
  env.session.api.call = async (_method, _path, payload) => { sent = JSON.parse(payload).display_name; return { display_name: sent }; };
  await env.session.setName('  新昵称  '); assert.equal(sent, '新昵称'); assert.equal(env.session.displayName, '新昵称');
  await assert.rejects(() => env.session.setName(' ')); await assert.rejects(() => env.session.setName('字'.repeat(31)));
});
test('chat: stale conversation fetch cannot overwrite a newer selection', async () => {
  const env = setup(); await login(env); const old = deferred(); const chat = new env.ChatStore(env.session);
  env.session.api.call = async (_method, endpoint) => endpoint.endsWith('/old') ? old.promise : { session_id: 'new', title: '新选择', messages: [] };
  const pending = chat.open('old'); await chat.open('new'); old.resolve({ session_id: 'old', title: '旧选择', messages: [] }); await pending;
  assert.equal(chat.activeId, 'new'); assert.equal(chat.title, '新选择');
});
test('chat: reset discards late stream callbacks', async () => {
  const env = setup(); await login(env); const gate = deferred(); let receive;
  env.session.api.stream = async (_run, _token, _control, callback) => { receive = callback; await gate.promise; };
  const chat = new env.ChatStore(env.session); const pending = chat.send('问题'); chat.reset();
  receive({ type: 'TEXT_MESSAGE_CONTENT', delta: '不应出现在新对话' }); gate.resolve(); await pending;
  assert.equal(chat.messages.length, 0); assert.equal(chat.streaming, false);
});
test('chat: waiting approval blocks new prompt and reset blocks late approval resume', async () => {
  const env = setup(); await login(env); let streams = 0;
  env.session.api.call = async () => [];
  env.session.api.stream = async (_run, _token, _control, callback) => { streams++; callback({ type: 'STATE_SNAPSHOT', snapshot: { approval_id: 'approval', message: '确认', tool_label: '操作', expires_at: '2099-01-01T00:00:00Z' } }); };
  const chat = new env.ChatStore(env.session); await chat.send('执行'); await chat.send('不应发送'); assert.equal(streams, 1);
  const gate = deferred(); env.session.api.call = async () => gate.promise;
  const pending = chat.approve('approve'); chat.reset(); gate.resolve({}); await pending;
  assert.equal(streams, 1); assert.equal(chat.messages.length, 0);
});
test('chat: stop cancels transport and calls existing cancellation contract', async () => {
  const env = setup(); await login(env); const gate = deferred(); let control, sent;
  env.session.api.stream = async (_run, _token, value) => { control = value; await gate.promise; };
  env.session.api.call = async (_method, endpoint, payload) => { sent = { endpoint, payload: JSON.parse(payload) }; return {}; };
  const chat = new env.ChatStore(env.session); const pending = chat.send('问题'); await chat.stop(); gate.resolve(); await pending;
  assert.equal(control.cancelled, true); assert.equal(chat.streaming, false); assert.equal(chat.messages[1].status, 'cancelled');
  assert.equal(sent.endpoint, '/api/v1/agent-runs/cancel'); assert.equal(sent.payload.reason, 'user_cancelled');
});
test('chat: expired approval clears the card and allows a new prompt', async () => {
  const env = setup(); await login(env); let streams = 0;
  env.session.api.call = async () => [];
  env.session.api.stream = async (_run, _token, _control, callback) => {
    streams++;
    if (streams === 1) callback({ type: 'STATE_SNAPSHOT', snapshot: { approval_id: 'approval', expires_at: '2000-01-01T00:00:00Z' } });
  };
  const chat = new env.ChatStore(env.session); await chat.send('执行'); await chat.approve('approve');
  assert.equal(chat.messages[1].approval, undefined); assert.equal(chat.messages[1].status, 'failed');
  await chat.send('重新提问'); assert.equal(streams, 2);
});
test('session: late password completion cannot mutate another signed-in account', async () => {
  const env = setup(); await login(env); const gate = deferred();
  env.session.api.call = async (_method, endpoint) => endpoint.endsWith('/change-password') ? gate.promise : {};
  const changing = env.session.changePassword('test-old', 'test-new');
  await env.session.signOut();
  env.session.api.call = async (method, endpoint) => endpoint.endsWith('/login') ? fixture({ user_id: 'second', has_password: false }) : env.account(method, endpoint);
  await env.session.signIn('login', '{}'); gate.resolve({}); await assert.rejects(changing);
  assert.equal(env.session.user.user_id, 'second'); assert.equal(env.session.user.has_password, false);
});
test('session: late invitation does not trigger an account reload after sign-out', async () => {
  const env = setup(); await login(env); const gate = deferred(); let reads = 0;
  env.session.api.call = async (_method, endpoint) => {
    if (endpoint.endsWith('/accept-invite')) return gate.promise;
    if (endpoint.endsWith('/workspaces')) reads++;
    return {};
  };
  const joining = env.session.join('test-invite'); await env.session.signOut(); gate.resolve({ message: 'joined' }); await assert.rejects(joining);
  assert.equal(reads, 0); assert.equal(env.session.state, 'signedOut');
});
for (const operation of ['rename', 'delete', 'pin']) {
  test(`chat: late ${operation} does not reset/reload another workspace`, async () => {
    const env = setup(); await login(env); const gate = deferred(); let reads = 0;
    env.session.api.call = async method => { if (method === 'GET') { reads++; return []; } return gate.promise; };
    const chat = new env.ChatStore(env.session); chat.activeId = 'same-id';
    const pending = chat[operation]({ session_id: 'same-id', title: 'old' }, 'new');
    env.session.revision++; chat.title = 'New workspace'; gate.resolve({}); await pending;
    assert.equal(chat.activeId, 'same-id'); assert.equal(chat.title, 'New workspace'); assert.equal(reads, 0);
  });
}
test('chat: streamed failure code and retryability survive subsequent immutable updates', async () => {
  const env = setup(); await login(env); env.session.api.call = async () => [];
  env.session.api.stream = async (_run, _token, _control, callback) => {
    callback({ type: 'RUN_ERROR', message: '  service unavailable  ', code: 'TEMPORARY_FAILURE' });
    callback({ type: 'RUN_FINISHED' });
  };
  const chat = new env.ChatStore(env.session); await chat.send('test');
  assert.equal(chat.messages[1].errorCode, 'TEMPORARY_FAILURE'); assert.equal(chat.messages[1].error, 'service unavailable');
  assert.equal(chat.messages[1].retryable, true); assert.equal(chat.messages[1].status, 'failed');
});

test('session: successful response after sign-out is rejected, not returned to a caller', async () => {
  const env = setup(); await login(env); const gate = deferred();
  const pending = env.session.authenticated(() => gate.promise);
  env.session.api.call = async () => ({});
  await env.session.signOut(); gate.resolve('old private data');
  await assert.rejects(pending); assert.equal(env.session.state, 'signedOut');
});
test('session: switch retry uses rotated refresh credential and resets old profile immediately', async () => {
  const env = setup(); await login(env); const sent = []; let releases = 0;
  env.session.avatar = { release() { releases++; } };
  env.session.api.call = async (method, endpoint, payload) => {
    if (endpoint.endsWith('/refresh')) return fixture({ token: 'rotated-access', refresh_token: 'rotated-refresh' });
    if (endpoint.endsWith('/workspaces/switch')) {
      sent.push(JSON.parse(payload).refresh_token);
      if (sent.length === 1) throw new ApiError(401, 'expired');
      return fixture({ active_workspace_id: 'w2', username: '新空间', refresh_token: 'switched-refresh' });
    }
    if (endpoint.endsWith('/profile')) throw new ApiError(503, 'offline');
    return env.account(method, endpoint);
  };
  await env.session.switchWorkspace('w2');
  assert.deepEqual(sent, ['test-refresh', 'rotated-refresh']);
  assert.equal(env.session.user.active_workspace_id, 'w2'); assert.equal(env.session.avatar, undefined);
  assert.equal(env.session.displayName, '新空间'); assert.equal(releases, 1);
});
test('session: an old refresh never blocks or detaches the new account refresh', async () => {
  const env = setup(); await login(env); const old = deferred(), current = deferred(); let refreshes = 0;
  env.session.api.call = async (method, endpoint) => {
    if (endpoint.endsWith('/refresh')) { refreshes++; return refreshes === 1 ? old.promise : current.promise; }
    if (endpoint.endsWith('/login')) return fixture({ user_id: 'second', token: 'second-access' });
    if (endpoint.endsWith('/logout')) return {};
    return env.account(method, endpoint);
  };
  const expired = async token => { if (!token.endsWith('-fresh')) throw new ApiError(401, 'expired'); return token; };
  const first = env.session.authenticated(expired); const firstRejected = assert.rejects(first);
  await new Promise(resolve => setImmediate(resolve)); await env.session.signOut(); await env.session.signIn('login', '{}');
  const second = env.session.authenticated(expired);
  await new Promise(resolve => setImmediate(resolve));
  old.resolve(fixture({ token: 'old-fresh' })); await firstRejected;
  const third = env.session.authenticated(expired);
  await new Promise(resolve => setImmediate(resolve)); current.resolve(fixture({ user_id: 'second', token: 'second-fresh' }));
  assert.deepEqual(await Promise.all([second, third]), ['second-fresh', 'second-fresh']); assert.equal(refreshes, 2);
});
test('session: unreadable vault does not prevent local logout', async () => {
  const env = setup(); await login(env); env.faults.read = true;
  await env.session.signOut(); assert.equal(env.session.user, undefined); assert.equal(env.stored(), '');
  assert.equal(env.session.state, 'signedOut');
});
test('session: failed credential removal clears memory and blocks restoration after restart', async () => {
  const env = setup(); await login(env); env.faults.clear = true;
  await env.session.signOut();
  assert.equal(env.session.state, 'cleanupError'); assert.equal(env.session.user, undefined);
  assert.equal(env.session.displayName, ''); assert.equal(env.blocked(), true);
  const restarted = env.restart(); let calls = 0; restarted.api.call = async () => { calls++; return fixture(); };
  await restarted.restore(); assert.equal(calls, 0); assert.equal(restarted.state, 'cleanupError');
  env.faults.clear = false; await restarted.restore();
  assert.equal(restarted.state, 'signedOut'); assert.equal(env.stored(), '');
});
test('session: failed secure write never publishes a signed-in account', async () => {
  const env = setup(); env.faults.write = true;
  env.session.api.call = async () => fixture();
  await assert.rejects(() => env.session.signIn('login', '{}'));
  assert.notEqual(env.session.state, 'signedIn'); assert.equal(env.session.user, undefined); assert.equal(env.stored(), '');
});
test('session: concurrent workspace switches send only one request', async () => {
  const env = setup(); await login(env); const gate = deferred(); let switches = 0;
  env.session.api.call = async (method, endpoint) => {
    if (endpoint.endsWith('/workspaces/switch')) { switches++; await gate.promise; return fixture({ active_workspace_id: 'w2' }); }
    return env.account(method, endpoint);
  };
  const first = env.session.switchWorkspace('w2'), second = env.session.switchWorkspace('w3');
  gate.resolve(); await Promise.all([first, second]); assert.equal(switches, 1);
});
test('chat: session change rejects stream callbacks before a page lifecycle reset', async () => {
  const env = setup(); await login(env); const gate = deferred(); let receive;
  env.session.api.stream = async (_run, _token, _control, callback) => { receive = callback; await gate.promise; };
  const chat = new env.ChatStore(env.session); const pending = chat.send('fixture');
  env.session.revision++; receive({ type: 'TEXT_MESSAGE_CONTENT', delta: 'old workspace text' });
  gate.resolve(); await pending; assert.equal(chat.messages[1].content, ''); assert.equal(chat.messages[1].error, '');
});
test('chat: an old workspace history failure cannot replace the new error state', async () => {
  const env = setup(); await login(env); const gate = deferred();
  env.session.api.call = async () => gate.promise; const chat = new env.ChatStore(env.session);
  const pending = chat.loadHistory(); env.session.revision++; chat.historyError = 'new workspace error';
  gate.reject(new ApiError(503, 'old workspace error')); await pending;
  assert.equal(chat.historyError, 'new workspace error');
  chat.stage = 'old'; chat.close(); assert.equal(chat.stage, ''); assert.equal(chat.historyError, ''); assert.equal(chat.historyLoading, false);
});
test('session: proactively refreshes a JWT expiring in six hours before sending account reads', async () => {
  const env = setup(); let refreshes = 0; const used = [];
  const jwt = exp => `fixture.${Buffer.from(JSON.stringify({ exp })).toString('base64url')}.signature`;
  env.session.api.call = async (method, endpoint, _payload, token) => {
    if (endpoint.endsWith('/login')) return fixture({ token: jwt(Math.floor(Date.now() / 1000) + 60) });
    if (endpoint.endsWith('/refresh')) { refreshes++; return fixture({ token: 'renewed-test-access' }); }
    used.push(token); return env.account(method, endpoint);
  };
  await env.session.signIn('login', '{}'); assert.equal(refreshes, 1); assert.ok(used.every(value => value === 'renewed-test-access'));
  assert.equal(env.session.shouldRefresh(jwt(Date.now() / 1000 + 7 * 3600)), false);
  assert.equal(env.session.shouldRefresh(jwt('not-a-number')), false);
  assert.equal(env.session.shouldRefresh('malformed.token'), false);
});
test('session: remembered workspace is restored only when still accessible to the same user', async () => {
  const env = setup(); env.remembered.set('test-user', 'w2'); env.remembered.set('second', 'private-other'); const switched = [];
  env.session.api.call = async (method, endpoint, payload) => {
    if (endpoint.endsWith('/login')) return fixture();
    if (endpoint.endsWith('/workspaces')) return { items: [{ workspace_id: 'w1' }, { workspace_id: 'w2' }] };
    if (endpoint.endsWith('/workspaces/switch')) {
      const id = JSON.parse(payload).workspace_id; switched.push(id); return fixture({ active_workspace_id: id });
    }
    return env.account(method, endpoint);
  };
  await env.session.signIn('login', '{}'); assert.deepEqual(switched, ['w2']); assert.equal(env.session.user.active_workspace_id, 'w2');
  env.remembered.set('test-user', 'no-longer-accessible'); switched.length = 0;
  await env.session.signIn('login', '{}'); assert.equal(switched.length, 0); assert.equal(env.remembered.get('test-user'), 'w1');
  assert.equal(env.remembered.get('second'), 'private-other');
});
test('session: storage failures cannot leave private account data visible or permit another login', async () => {
  const env = setup(); await login(env); env.faults.clear = true; env.faults.preferences = true;
  await env.session.signOut(); assert.equal(env.session.state, 'cleanupError'); assert.equal(env.session.user, undefined);
  assert.match(env.session.error, /请勿关闭应用/); await assert.rejects(() => env.session.signIn('login', '{}'));
  env.faults.clear = false; env.faults.preferences = false; await env.session.restore();
  assert.equal(env.session.state, 'signedOut'); await login(env); assert.equal(env.session.state, 'signedIn'); assert.equal(env.blocked(), false);
});
