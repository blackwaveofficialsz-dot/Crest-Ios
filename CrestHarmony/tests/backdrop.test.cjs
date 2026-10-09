const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

// Execute the real drawing/lifecycle methods without the ArkUI build DSL.
function setup() {
  const calls = [];
  const intervals = new Map();
  let nextTimer = 0;
  class Canvas {
    constructor() { this.width = 360; this.height = 800; }
    reset() { calls.push(['reset']); }
    fillRect(...args) { calls.push(['fill', ...args]); }
    beginPath() {} moveTo() {} lineTo() {} closePath() {} fill() {}
    createLinearGradient() { return { addColorStop() {} }; }
  }
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/LoginBackdrop.ets'), 'utf8')
    .replace('@Component', '').replace('export struct', 'export class')
    .replace(/@StorageLink\('foreground'\) @Watch\('updateActivity'\) /, '')
    .replace(/@StorageLink\('reduceMotion'\) @Watch\('updateActivity'\) /, '')
    .split('  build() {')[0] + '}';
  const module = { exports: {} };
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports,
    CanvasRenderingContext2D: Canvas, RenderingContextSettings: class {},
    setInterval: callback => { const id = ++nextTimer; intervals.set(id, callback); return id; },
    clearInterval: id => intervals.delete(id)
  });
  return { backdrop: new module.exports.LoginBackdrop(), calls, intervals };
}

test('login backdrop: each animation frame resets the canvas buffer and state before repainting', () => {
  const { backdrop, calls } = setup();
  for (const time of [0, 0.05, 30, 300]) {
    calls.length = 0;
    backdrop.draw(time);
    assert.deepEqual(calls[0], ['reset']);
    assert.deepEqual(calls[1], ['fill', 0, 0, 360, 800]);
    assert.equal(calls.filter(call => call[0] === 'reset').length, 1);
  }
});

test('login backdrop: background and disappearance stop drawing without duplicate timers', () => {
  const { backdrop, intervals } = setup();
  backdrop.updateActivity();
  assert.equal(intervals.size, 0);
  backdrop.ready = true;
  backdrop.updateActivity(); backdrop.updateActivity();
  assert.equal(intervals.size, 1);
  backdrop.foreground = false; backdrop.updateActivity();
  assert.equal(intervals.size, 0);
  backdrop.foreground = true; backdrop.updateActivity();
  assert.equal(intervals.size, 1);
  backdrop.aboutToDisappear();
  assert.equal(intervals.size, 0);
  backdrop.updateActivity();
  assert.equal(intervals.size, 0);
});

test('login backdrop: reduced motion freezes the image and resumes only when enabled again', () => {
  const { backdrop, calls, intervals } = setup();
  backdrop.ready = true;
  backdrop.updateActivity();
  assert.equal(intervals.size, 1);
  calls.length = 0;
  backdrop.reduceMotion = true;
  backdrop.updateActivity();
  assert.equal(intervals.size, 0);
  assert.deepEqual(calls[0], ['reset']);
  backdrop.updateActivity();
  assert.equal(intervals.size, 0);
  backdrop.reduceMotion = false;
  backdrop.updateActivity();
  assert.equal(intervals.size, 1);
});
