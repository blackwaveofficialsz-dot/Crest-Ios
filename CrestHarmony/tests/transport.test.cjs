const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function setup(fetch) {
  let closed = 0;
  class Request {
    constructor(url, method, headers, content) { Object.assign(this, { url, method, headers, content }); }
  }
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/Api.ets'), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  const localRequire = name => {
    if (name === '@kit.NetworkKit') return { http: {} };
    if (name === '@kit.RemoteCommunicationKit') return { rcp: { Request, createSession: () => ({ fetch, close: () => closed++ }) } };
    if (name === '@kit.ArkTS') return { util: {} };
    if (name.endsWith('/Protocol')) return require('../work/test-core/Protocol');
    throw new Error(`Unexpected import ${name}`);
  };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, require: localRequire, Error, Promise, JSON });
  return { api: new module.exports.Api(), ApiError: module.exports.ApiError, closed: () => closed };
}
test('transport: PATCH retains method, JSON and bearer headers on the API 12 bridge', async () => {
  const env = setup(async request => {
    assert.equal(request.method, 'PATCH');
    assert.equal(request.url, 'https://blackwave.org.cn/yuanji/api/v1/auth/profile');
    assert.equal(request.headers.Authorization, 'Bearer fixture-only');
    assert.equal(request.headers['Content-Type'], 'application/json');
    assert.equal(request.content, '{"display_name":"test"}');
    assert.equal(request.configuration.transfer.autoRedirect, false);
    assert.equal(request.configuration.transfer.timeout.connectMs, 20000);
    assert.equal(request.configuration.transfer.timeout.transferMs, 60000);
    return { statusCode: 200, toString: () => '{"display_name":"test"}' };
  });
  const result = await env.api.call('PATCH', '/api/v1/auth/profile', '{"display_name":"test"}', 'fixture-only');
  assert.equal(result.display_name, 'test'); assert.equal(env.closed(), 1);
});
test('transport: GET does not send an empty body or unauthenticated bearer header', async () => {
  const env = setup(async request => {
    assert.equal(request.content, undefined); assert.equal(request.headers.Authorization, undefined);
    assert.equal(request.headers['Content-Type'], undefined);
    return { statusCode: 204, toString: () => null };
  });
  assert.equal(JSON.stringify(await env.api.call('GET', '/test')), '{}'); assert.equal(env.closed(), 1);
});
test('transport: 401 preserves ApiError identity for session refresh and closes the bridge', async () => {
  const env = setup(async () => ({ statusCode: 401, toString: () => '{"detail":"expired"}' }));
  await assert.rejects(env.api.call('GET', '/test'), error => error instanceof env.ApiError && error.status === 401 && error.message === 'expired');
  assert.equal(env.closed(), 1);
});
test('transport: malformed JSON still releases the native session', async () => {
  const env = setup(async () => ({ statusCode: 200, toString: () => 'not-json' }));
  await assert.rejects(env.api.call('GET', '/test')); assert.equal(env.closed(), 1);
});
test('transport: network rejection releases the native session', async () => {
  const failure = new Error('fixture offline');
  const env = setup(async () => { throw failure; });
  await assert.rejects(env.api.call('GET', '/test'), error => error === failure); assert.equal(env.closed(), 1);
});
