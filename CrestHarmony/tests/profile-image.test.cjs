const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const protocol = require('../work/test-core/Protocol');

// Execute the shipped editor methods, replacing only native image/picker/network boundaries.
function editor({ orientation = 'Right-top', pack, pick, getWindow, setBars } = {}) {
  const source = fs.readFileSync('entry/src/main/ets/components/ProfileEditor.ets', 'utf8');
  const methods = source.slice(source.indexOf('  private setBusy('), source.indexOf('  private async saveName('));
  const calls = [], decoded = {
    flip: async (...args) => calls.push(['flip', ...args]),
    rotate: async angle => calls.push(['rotate', angle]),
    getImageInfo: async () => ({ size: { width: 1024, height: 2048 } }),
    release: () => calls.push(['releasePreview'])
  };
  class Canvas {
    constructor(...args) { calls.push(['canvas', ...args]); }
    fillRect(...args) { calls.push(['fill', this.fillStyle, ...args]); }
    drawImage(_image, ...args) { calls.push(['draw', ...args]); }
    getPixelMap(...args) { calls.push(['output', ...args]); return { release: () => calls.push(['releaseOutput']) }; }
  }
  const previousBars = { statusBarColor: '#F2F2F7', statusBarContentColor: '#000000', navigationBarColor: '#F2F2F7', navigationBarContentColor: '#000000' };
  const host = {
    getWindowAvoidArea: type => ({ topRect: { height: type === 'system' ? 140 : 0 }, bottomRect: { height: type === 'navigation' ? 70 : 0 } }),
    getWindowSystemBarProperties: () => previousBars,
    setWindowSystemBarProperties: async bars => { calls.push(['bars', bars]); if (setBars) await setBars(bars); }
  };
  const native = {
    window: { AvoidAreaType: { TYPE_SYSTEM: 'system', TYPE_NAVIGATION_INDICATOR: 'navigation' },
      getLastWindow: () => getWindow ? getWindow(host) : Promise.resolve(host) },
    ...protocol, LengthMetricsUnit: { PX: 'px' }, RenderingContextSettings: class {}, OffscreenCanvasRenderingContext2D: Canvas,
    ApiError: class extends Error { constructor(_code, message) { super(message); } }, errorText: e => e.message,
    fs: { OpenMode: { READ_ONLY: 1 }, openSync: () => ({ fd: 7 }), closeSync: () => calls.push(['closeFile']) },
    photoAccessHelper: { PhotoViewMIMETypes: { IMAGE_TYPE: 'image' }, PhotoViewPicker: class { select() { return pick ? pick() : Promise.resolve({ photoUris: ['fixture'] }); } } },
    image: { PropertyKey: { ORIENTATION: 'Orientation' },
      createImageSource: () => ({ getImageInfo: async () => ({ size: { width: 4000, height: 2000 } }),
        createPixelMap: async options => { calls.push(['decode', options.desiredSize]); return decoded; },
        getImageProperty: async () => orientation, release: () => calls.push(['releaseSource']) }),
      createImagePacker: () => ({ packing: async (_map, options) => { calls.push(['pack', options]); return pack ? pack(options.quality) : new ArrayBuffer(128); }, release: () => calls.push(['releasePacker']) }) }
  };
  const js = ts.transpileModule(`class Editor { ${methods} }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const form = vm.runInNewContext(js + ';new Editor()', native);
  Object.assign(form, { alive: true, busy: false, error: '', notice: '', cropping: false, session: { revision: 1, setAvatar: async data => calls.push(['upload', data.byteLength]) },
    t: key => key, onBusyChange: () => {}, getUIContext: () => ({ getHostContext: () => ({}), px2vp: value => value / 3.5,
      getFocusController: () => ({ clearFocus() {} }) }), viewport: 300 });
  return { form, calls, decoded, previousBars };
}

test('avatar: all eight EXIF values map mirror before rotation, unknown metadata stays upright', () => {
  const names = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left', 'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];
  const expected = [[0,0,0],[0,1,0],[180,0,0],[0,0,1],[270,1,0],[90,0,0],[90,1,0],[270,0,0]];
  names.forEach((name, i) => { assert.deepEqual(protocol.avatarOrientation(name), expected[i]); assert.deepEqual(protocol.avatarOrientation(String(i + 1)), expected[i]); });
  assert.deepEqual(protocol.avatarOrientation('Unknown'), [0,0,0]);
});
test('avatar: decode capped at 2048, normalize mirrored image before measuring and close source/file', async () => {
  const { form, calls, decoded } = editor({ orientation: 'Left-top' }); await form.choosePhoto();
  assert.equal(JSON.stringify(calls.find(c => c[0] === 'decode')[1]), '{"width":2048,"height":1024}');
  assert.deepEqual(calls.filter(c => ['flip','rotate'].includes(c[0])), [['flip',true,false],['rotate',270]]);
  assert.equal(form.preview, decoded); assert.equal(form.imageWidth, 1024); assert.equal(form.imageHeight, 2048);
  assert.equal(form.cropping, true); assert.equal(form.busy, false);
  assert.equal(calls.filter(c => c[0] === 'upload').length, 0, 'selection must never save an avatar');
  assert.ok(calls.some(c => c[0] === 'closeFile')); assert.ok(calls.some(c => c[0] === 'releaseSource'));
});
test('avatar: canceled or stale photo picker never opens crop or uploads', async () => {
  for (const canceled of [true, false]) {
    let resolve; const { form, calls } = editor({ pick: () => new Promise(r => resolve = r) });
    const pending = form.choosePhoto(); if (!canceled) form.session.revision++;
    resolve({ photoUris: canceled ? [] : ['fixture'] }); await pending;
    assert.equal(form.cropping, false); assert.equal(calls.length, 0); assert.equal(form.busy, false);
  }
});
test('avatar: output is 512 physical pixels with black alpha backing and iOS JPEG quality ladder', async () => {
  const { form, calls } = editor({ pack: q => new ArrayBuffer(q === 82 ? 1024 * 1024 + 1 : 120) });
  await form.choosePhoto(); await form.savePhoto();
  assert.equal(calls.find(c => c[0] === 'canvas')[4], 'px');
  assert.deepEqual(calls.find(c => c[0] === 'output'), ['output',0,0,512,512]);
  assert.deepEqual(calls.find(c => c[0] === 'fill'), ['fill','#000000',0,0,512,512]);
  assert.deepEqual(calls.filter(c => c[0] === 'pack').map(c => c[1].quality), [82,68]);
  assert.deepEqual(calls.find(c => c[0] === 'upload'), ['upload',120]); assert.equal(form.cropping, false);
});
test('avatar: oversize encoding stays on crop with actionable error and no upload', async () => {
  const { form, calls } = editor({ pack: () => new ArrayBuffer(1024 * 1024 + 1) });
  await form.choosePhoto(); await form.savePhoto();
  assert.equal(form.cropping, true); assert.equal(form.error, '无法处理所选图片'); assert.equal(form.busy, false);
  assert.equal(calls.filter(c => c[0] === 'upload').length, 0);
  assert.deepEqual(calls.filter(c => c[0] === 'pack').map(c => c[1].quality), [82,68,52]);
});
test('avatar: leaving or switching while encoding prevents late account writes; duplicate tap ignored', async () => {
  for (const event of ['close','switch']) {
    let resolve; const { form, calls } = editor({ pack: () => new Promise(r => resolve = r) });
    await form.choosePhoto(); const pending = form.savePhoto(); await form.savePhoto();
    if (event === 'close') form.alive = false; else form.session.revision++;
    resolve(new ArrayBuffer(12)); await pending;
    assert.equal(calls.filter(c => c[0] === 'upload').length, 0); assert.equal(calls.filter(c => c[0] === 'pack').length, 1);
    assert.equal(form.error, ''); assert.equal(form.busy, false);
    assert.equal(form.preview, undefined);
  }
});
test('avatar: narrow images never create a zero-size crop at maximum zoom', () => {
  assert.equal(protocol.cropRegion(1, 2048, 4, 0, 0, 300)[2], 1);
});
test('avatar: full-screen toolbar and crop respect density-adjusted system safe areas', async () => {
  const { form } = editor(); form.cropping = true; await form.updateCropInsets();
  assert.equal(form.cropTop, 40); assert.equal(form.cropBottom, 20);
  form.alive = false; form.cropTop = 0; await form.updateCropInsets();
  assert.equal(form.cropTop, 0, 'closed editor must ignore window response');
});
test('avatar: black crop uses white status text once and restores the exact previous bars', async () => {
  const { form, calls, previousBars } = editor(); form.cropping = true;
  await form.updateCropInsets(); await form.updateCropInsets();
  assert.equal(calls.length, 1);
  assert.equal(calls[0][1].statusBarContentColor, '#FFFFFF');
  assert.equal(calls[0][1].statusBarColor, '#000000');
  form.cropping = false; await form.restoreCropBars(); await form.restoreCropBars();
  assert.equal(calls.length, 2); assert.equal(calls[1][1], previousBars);
});
test('avatar: a late window lookup never changes bars after the crop closes', async () => {
  let resolve; const { form, calls } = editor({ getWindow: host => new Promise(r => resolve = () => r(host)) });
  form.cropping = true; const pending = form.updateCropInsets();
  form.cropping = false; resolve(); await pending;
  assert.equal(calls.length, 0);
});
test('avatar: close waits for an in-flight crop bar update before restoring', async () => {
  let resolve, started;
  const updating = new Promise(r => started = r);
  const { form, calls, previousBars } = editor({ setBars: bars => bars === previousBars ? undefined : new Promise(r => { resolve = r; started(); }) });
  form.cropping = true; const pending = form.updateCropInsets(); await updating;
  form.cropping = false; const restored = form.restoreCropBars();
  assert.equal(calls.length, 1); resolve(); await pending; await restored;
  assert.equal(calls.length, 2); assert.equal(calls[1][1], previousBars);
});
