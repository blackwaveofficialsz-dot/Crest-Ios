const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('typescript');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const config = file => JSON.parse(read(file)); // Our JSON5 manifests intentionally use strict JSON syntax.
const files = directory => fs.readdirSync(path.join(root, directory), { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? files(`${directory}/${entry.name}`) : [`${directory}/${entry.name}`]);
assert.equal(config('AppScope/app.json5').app.bundleName, 'com.blackwave.crest');
assert.equal(config('build-profile.json5').app.products[0].runtimeOS, 'HarmonyOS');
const moduleConfig = config('entry/src/main/module.json5').module;
assert.deepEqual(moduleConfig.requestPermissions.map(permission => permission.name), ['ohos.permission.INTERNET']);
const sourceFiles = files('entry/src/main/ets');
for (const file of sourceFiles) {
  const source = read(file);
  for (const match of source.matchAll(/from\s+['"](\.[^'"]+)['"]/g)) {
    const target = path.resolve(root, path.dirname(file), match[1]);
    assert.ok(['.ts', '.ets'].some(extension => fs.existsSync(target + extension)), `${file}: unresolved ${match[1]}`);
  }
  assert.ok(!/\b(console\.|hilog\.)/.test(source), `${file}: sensitive logging review required`);
  assert.ok(!/Web\(\s*\{|WebviewController|@kit\.ArkWeb/.test(source), `${file}: native UI must not be replaced by a WebView`);
  if (file.includes('/services/') || file.includes('/state/')) {
    const parsed = ts.createSourceFile(file + '.ts', source, ts.ScriptTarget.Latest, true);
    assert.equal(parsed.parseDiagnostics.length, 0, `${file}: TS syntax: ${parsed.parseDiagnostics.map(d => d.messageText).join(', ')}`);
  }
}
for (const page of config('entry/src/main/resources/base/profile/main_pages.json').src) assert.ok(fs.existsSync(path.join(root, 'entry/src/main/ets', page + '.ets')));
assert.ok(read('entry/src/main/ets/services/TokenStore.ets').includes('asset.SyncType.NEVER'));
assert.ok(read('entry/src/main/ets/services/Api.ets').includes("https://blackwave.org.cn/yuanji"));
for (const name of ['rubik_regular.ttf', 'rubik_bold.ttf', 'Rubik-OFL.txt']) assert.ok(fs.existsSync(path.join(root, 'entry/src/main/resources/rawfile/fonts', name)));
console.log(`Project checks passed: ${sourceFiles.length} source files; relative imports, manifests, native-only UI, permissions, font license, logging, service syntax.`);
console.log('This does NOT validate ArkUI DSL, HarmonyOS SDK types, HAP packaging or device behavior.');
