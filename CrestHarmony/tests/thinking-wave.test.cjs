const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function wave() {
  const strokes = [], intervals = new Map(); let nextId = 0;
  class Canvas {
    width = 48; height = 24;
    reset() { strokes.length = 0; }
    beginPath() {} moveTo() {} lineTo() {}
    stroke() { strokes.push({ width: this.lineWidth, color: this.strokeStyle }); }
  }
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/RichMessage.ets'), 'utf8');
  const component = source.slice(source.indexOf('@Component\nstruct ThinkingWave'), source.indexOf('@Component\nexport struct RichMessage'))
    .replace('@Component', '').replace('struct ThinkingWave', 'class ThinkingWave')
    .replace(/@StorageLink\('foreground'\) @Watch\('updateActivity'\) /, '')
    .replace(/@StorageLink\('reduceMotion'\) @Watch\('updateActivity'\) /, '')
    .slice(0, -2);
  const sourceOnly = component.split('  build() {')[0] + '}';
  const compiled = ts.transpileModule(sourceOnly, { compilerOptions: { target: ts.ScriptTarget.ES2020 } });
  const Wave = vm.runInNewContext(compiled.outputText + ';ThinkingWave', {
    CanvasRenderingContext2D: Canvas, RenderingContextSettings: class {},
    setInterval: callback => { const id = ++nextId; intervals.set(id, callback); return id; },
    clearInterval: id => intervals.delete(id)
  });
  return { component: new Wave(), strokes, intervals };
}

test('thinking wave: draws the iOS ribbon and three fine contours', () => {
  const { component, strokes } = wave();
  component.draw(0.22);
  assert.deepEqual(strokes.map(stroke => stroke.width), [9, 0.85, 0.85, 0.85]);
  assert.equal(strokes[0].color, 'rgba(255,255,255,0.96)');
});

test('thinking wave: reduced motion freezes animation and disappearance releases the timer', () => {
  const { component, intervals } = wave();
  component.ready = true;
  component.updateActivity(); assert.equal(intervals.size, 1);
  component.reduceMotion = true; component.updateActivity(); assert.equal(intervals.size, 0);
  component.reduceMotion = false; component.updateActivity(); assert.equal(intervals.size, 1);
  component.foreground = false; component.updateActivity(); assert.equal(intervals.size, 0);
  component.foreground = true; component.updateActivity(); assert.equal(intervals.size, 1);
  component.aboutToDisappear(); assert.equal(intervals.size, 0);
});
