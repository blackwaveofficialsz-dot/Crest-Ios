const test = require('node:test');
const assert = require('node:assert/strict');
const { SSEDecoder, EventValidator, runBody, supportedParts, supportedActions, historyMessage, validPhone, validPassword, safeLink, cropRegion } = require('../work/test-core/Protocol');

function wire(type, sequence, fields = {}) {
  const event = { type, sequence, eventId: `run:${sequence}:0`, runId: 'run', threadId: 'thread', ...fields };
  return { id: event.eventId, data: JSON.stringify(event) };
}
const response = fields => ({ version: 1, source_turn_id: 'turn', ...fields });
test('SSE: arbitrary boundaries, CRLF, heartbeat, multiline and EOF', () => {
  const frames = []; const decoder = new SSEDecoder(frame => frames.push(frame));
  const source = ': keepalive\r\nid: r:1:0\r\ndata: {"a":\r\ndata: "你好"}\r\n\r\nid: r:2:0\ndata: second';
  for (let i = 0; i < source.length; i += 3) decoder.feed(source.slice(i, i + 3));
  decoder.finish();
  assert.deepEqual(frames, [{ id: 'r:1:0', data: '{"a":\n"你好"}' }, { id: 'r:2:0', data: 'second' }]);
});
test('SSE: empty frames and comments never deliver events', () => {
  const frames = []; const decoder = new SSEDecoder(frame => frames.push(frame));
  decoder.feed(': hello\n\n\nid: unused\n\n'); decoder.finish(); assert.deepEqual(frames, []);
});
test('SSE: missing blank line flushes when next event id begins', () => {
  const frames = []; const decoder = new SSEDecoder(frame => frames.push(frame));
  decoder.feed('id: one\ndata: first\nid: two\ndata: second\n\n'); assert.equal(frames.length, 2);
});
test('SSE: oversized unterminated line is rejected', () => {
  assert.throws(() => new SSEDecoder(() => {}).feed('a'.repeat(2 * 1024 * 1024 + 1)), /过大/);
});
test('SSE: multiline oversized frame is also rejected', () => {
  const decoder = new SSEDecoder(() => {});
  assert.throws(() => { for (let i = 0; i < 2200; i++) decoder.feed('data: ' + 'x'.repeat(1024) + '\n'); }, /过大/);
});
test('protocol: deltas require a matching assistant start', () => {
  const validator = new EventValidator('thread', 'run');
  assert.throws(() => validator.parse(wire('TEXT_MESSAGE_CONTENT', 1, { messageId: 'm', delta: 'a' })), /关联/);
  validator.parse(wire('TEXT_MESSAGE_START', 2, { messageId: 'm', role: 'assistant' }));
  assert.equal(validator.parse(wire('TEXT_MESSAGE_CONTENT', 3, { messageId: 'm', delta: '你好' })).delta, '你好');
  assert.throws(() => validator.parse(wire('TEXT_MESSAGE_CONTENT', 4, { messageId: 'other', delta: 'a' })), /关联/);
});
test('protocol: reconnect replays are deduplicated without losing active message', () => {
  const validator = new EventValidator('thread', 'run');
  const start = wire('TEXT_MESSAGE_START', 1, { messageId: 'm', role: 'assistant' });
  const delta = wire('TEXT_MESSAGE_CONTENT', 2, { messageId: 'm', delta: 'a' });
  validator.parse(start); validator.parse(delta);
  assert.equal(validator.parse(start), undefined); assert.equal(validator.parse(delta), undefined);
  assert.equal(validator.parse(wire('TEXT_MESSAGE_CONTENT', 3, { messageId: 'm', delta: 'b' })).delta, 'b');
});
test('protocol: cross-thread/run and mismatched SSE id are rejected', () => {
  const validator = new EventValidator('thread', 'run');
  assert.throws(() => validator.parse(wire('RUN_STARTED', 1, { threadId: 'other' })), /协议/);
  assert.throws(() => validator.parse(wire('RUN_STARTED', 1, { runId: 'other' })), /协议/);
  assert.throws(() => validator.parse({ id: 'wrong', data: wire('RUN_STARTED', 1).data }), /游标/);
  assert.throws(() => validator.parse(wire('RUN_STARTED', 2, { eventId: 'run:1:0' })), /游标/);
});
test('protocol: noninteger sequence, invalid JSON and non-assistant starts rejected', () => {
  const validator = new EventValidator('thread', 'run');
  assert.throws(() => validator.parse(wire('RUN_STARTED', 1.5)));
  assert.throws(() => validator.parse({ id: '', data: '{' }));
  assert.throws(() => validator.parse(wire('TEXT_MESSAGE_START', 1, { messageId: 'm', role: 'user' })));
});
test('run body uses Android AGUI field casing, stable identities and resume cursor', () => {
  const interaction = { kind: 'clarification_choice', source_turn_id: 'turn', candidate_id: 'candidate' };
  const data = runBody('t', 'r', 'm', '你好', 'r:12:0', interaction);
  assert.deepEqual(data, { threadId: 't', runId: 'r', parentRunId: null, state: {}, messages: [{ id: 'm', role: 'user', content: '你好' }], tools: [], context: [], forwardedProps: { afterEventId: 'r:12:0', interaction } });
  assert.deepEqual(runBody('t', 'r', 'm', 'hi').forwardedProps, {});
});
test('AGUI: supported five card types and bounded card count', () => {
  const parts = [{ kind: 'table', columns: [{ key: 'a', label: '列' }] }, { kind: 'summary', message: '摘要' }, { kind: 'insights', items: [{ text: '洞察' }] }, { kind: 'notice', message: '提醒', severity: 'warning' }, { kind: 'clarification', message: '请选择' }];
  assert.equal(supportedParts(response({ parts })).length, 5);
  assert.equal(supportedParts(response({ parts: Array(20).fill(parts[1]) })).length, 6);
});
test('AGUI: malformed/future metadata does not make unusable cards', () => {
  assert.deepEqual(supportedParts({ version: 2, source_turn_id: 'turn', parts: [{ kind: 'summary', message: 'a' }] }), []);
  assert.deepEqual(supportedParts(response({ parts: [null, { kind: 'summary', message: 5 }, { kind: 'notice', message: 'x', severity: 'unknown' }, { kind: 'table', columns: [null] }, { kind: 'insights', items: [null] }] })), []);
});
test('AGUI: actions require matching source turn and complete parameters', () => {
  const good = { action_id: 'a', kind: 'clarify', label: '选择门店', source_turn_id: 'turn', params: { candidate_id: 's', message: '这家店' } };
  const actions = supportedActions(response({ actions: [good, { ...good, source_turn_id: 'other' }, { ...good, params: { message: 'missing id' } }, { ...good, kind: 'unknown' }, { ...good, label: 4 }] }));
  assert.deepEqual(actions, [good]);
  assert.equal(supportedActions(response({ actions: [{ ...good, kind: 'prompt', params: { message: 'go' } }] })).length, 1);
});
test('history: unknown roles hidden, legacy text kept, failure visible', () => {
  assert.deepEqual(historyMessage({ id: '1', role: 'tool', content: 'private' }), []);
  const item = historyMessage({ id: '2', role: 'assistant', content: 'legacy', metadata: { agent_response: { version: 9 }, delivery_status: 'failed' } })[0];
  assert.equal(item.content, 'legacy'); assert.equal(item.error, 'legacy'); assert.deepEqual(item.parts, []);
});
test('phone/password boundaries match existing clients', () => {
  assert.equal(validPhone('19900000000'), true); assert.equal(validPhone('1990000000'), false); assert.equal(validPhone('+8619900000000'), false);
  assert.equal(validPassword('a'.repeat(6)), false); assert.equal(validPassword('a'.repeat(7)), true); assert.equal(validPassword('a'.repeat(16)), true); assert.equal(validPassword('a'.repeat(17)), false);
});
test('only external HTTP(S) links are launched', () => {
  for (const url of ['javascript:alert(1)', 'file:///private/data', 'data:text/html,x', 'intent://private', '//example.org']) assert.equal(safeLink(url), false);
  assert.equal(safeLink('https://example.org/a?q=1'), true);
});
test('avatar crop: centered portrait/landscape square', () => {
  assert.deepEqual(cropRegion(1200, 800, 1, 0, 0, 260), [200, 0, 800]);
  assert.deepEqual(cropRegion(800, 1200, 2, 0, 0, 260), [200, 400, 400]);
});
test('avatar crop: pan and zoom remain inside decoded image', () => {
  for (const width of [12, 800, 2048]) for (const height of [16, 600, 2048]) for (const zoom of [.1, 1, 4, 10]) for (const x of [-10000, 0, 10000]) {
    const [left, top, side] = cropRegion(width, height, zoom, x, -x, 260);
    assert.ok(left >= 0 && top >= 0 && side > 0 && left + side <= width && top + side <= height);
  }
});
