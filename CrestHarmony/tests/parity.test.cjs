// Logic/resource parity tests, not an ArkUI render or HarmonyOS SDK compilation test.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const { resolvedLocale, translate, localizedFormat } = require('../work/test-core/Localization');
const { IOS_ENGLISH } = require('../work/test-core/IOSStrings');
const { displayCell, tableRows, formatMetric, formatTableValue } = require('../work/test-core/ResponseFormat');
const { MarkdownBlockCache, markdown } = require('../work/test-core/Markdown');
const { analyticsExportRows, dimensionDetail, laborDetail, alertDetail } = require('../work/test-core/Analytics');
const range = { date_from: '2026-09-01', date_to: '2026-09-30' };

test('language: explicit choice overrides system and system Chinese variants resolve consistently', () => {
  assert.equal(resolvedLocale('system', 'zh-Hant-TW'), 'zh-Hans');
  assert.equal(resolvedLocale('system', 'en-US'), 'en');
  assert.equal(resolvedLocale('system', 'ja-JP'), 'en');
  assert.equal(resolvedLocale('en', 'zh-CN'), 'en');
  assert.equal(resolvedLocale('zh-Hans', 'en-US'), 'zh-Hans');
});
test('language: generated catalog is current with every iOS English translation', () => {
  const source = JSON.parse(fs.readFileSync(path.join(__dirname, '../../Crest/Localizable.xcstrings'), 'utf8'));
  const english = Object.fromEntries(Object.entries(source.strings).flatMap(([key, value]) => {
    const text = value.localizations?.en?.stringUnit?.value;
    return typeof text === 'string' ? [[key, text]] : [];
  }));
  assert.ok(Object.keys(english).length >= 400);
  assert.deepEqual(IOS_ENGLISH, english);
  for (const [key, value] of Object.entries(english)) {
    assert.equal(translate(key, 'en'), value); assert.equal(translate(key, 'zh-Hans'), key);
  }
});
test('language: placeholders are substituted once and arbitrary server/user content is unchanged', () => {
  assert.equal(localizedFormat('显示 %@ / %@ 行', 'en', ['3', '20']), 'Showing 3 / 20 rows');
  assert.equal(localizedFormat('%@ / %lld / %%', 'zh-Hans', ['%@ user text', '2']), '%@ user text / 2 / %');
  assert.equal(translate('用户自行输入的门店名称', 'en'), '用户自行输入的门店名称');
  assert.equal(translate('https://example.org/a?token=example', 'en'), 'https://example.org/a?token=example');
});
test('language: every static Chinese UI label has an English counterpart', () => {
  const missing = new Set();
  for (const dir of ['components', 'pages']) {
    const root = path.join(__dirname, '../entry/src/main/ets', dir);
    for (const file of fs.readdirSync(root).filter(name => name.endsWith('.ets'))) {
      const ast = ts.createSourceFile(file + '.ts', fs.readFileSync(path.join(root, file), 'utf8'), ts.ScriptTarget.Latest, true);
      function visit(node) {
        if (ts.isStringLiteral(node) && /[\u3400-\u9fff]/u.test(node.text) && translate(node.text, 'en') === node.text) missing.add(node.text);
        ts.forEachChild(node, visit);
      }
      visit(ast);
    }
  }
  assert.deepEqual([...missing].sort(), []);
});
test('AGUI: nested JSON cells match iOS sorted object keys, arrays, booleans and null', () => {
  assert.equal(displayCell({ z: true, a: [0, null, { b: '门店' }] }), 'a: 0, —, b: 门店, z: true');
  assert.equal(displayCell(false), 'false'); assert.equal(displayCell([]), '');
  assert.deepEqual(tableRows({ columns: [{ key: 'details', label: '明细' }], preview_rows: [{ details: { count: 0 } }] }), [['count: 0']]);
});
test('AGUI: English units and comparison status use the iOS catalog', () => {
  for (const [unit, key] of [['order', '%@单'], ['store', '%@家'], ['hour', '%@小时'], ['period', '%@期'], ['product', '%@种'], ['item', '%@件'], ['person', '%@人']]) {
    assert.equal(formatMetric({ key: 'value', value: '12', unit }, 'en'), localizedFormat(key, 'en', ['12']));
    assert.equal(formatTableValue(12, { key: 'value', data_type: 'integer', unit }, 'en'), localizedFormat(key, 'en', ['12']));
  }
  assert.equal(formatTableValue('comparable', { key: 'comparison_status' }, 'en'), translate('可比', 'en'));
});
test('resources: both Harmony icon resources exactly match the current iOS app icon', () => {
  const ios = path.join(__dirname, '../../Crest/Assets.xcassets/AppIcon.appiconset');
  const manifest = JSON.parse(fs.readFileSync(path.join(ios, 'Contents.json'), 'utf8'));
  const icon = manifest.images.find(item => item.filename);
  const source = fs.readFileSync(path.join(ios, icon.filename));
  for (const resource of ['AppScope/resources/base/media/app_icon.png', 'entry/src/main/resources/base/media/app_icon.png']) {
    assert.deepEqual(fs.readFileSync(path.join(__dirname, '..', resource)), source);
  }
});
test('icons: path viewport and stroke share pixel units while layout remains density independent', () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/Theme.ets'), 'utf8');
  const icon = source.slice(source.indexOf('export struct CrestIcon'), source.indexOf('export struct IconButton'));
  assert.match(icon, /viewPort\(\{ x: 0, y: 0, width: '24px', height: '24px' \}\)/);
  assert.match(icon, /strokeWidth\('1\.7px'\)/);
  assert.match(icon, /\.width\(this\.iconSize\)\.height\(this\.iconSize\)/);
});
test('Markdown cache: freezes completed paragraphs and preserves their object identity', () => {
  const cache = new MarkdownBlockCache();
  cache.update('已完成\n\n回复', true);
  const first = cache.blocks[0];
  cache.update('已完成\n\n回复继续', true);
  assert.strictEqual(cache.blocks[0], first);
  assert.equal(cache.blocks[1].text, '回复继续');
  const unchanged = cache.blocks;
  cache.update('已完成\n\n回复继续', true);
  assert.strictEqual(cache.blocks, unchanged);
});
test('Markdown cache: each incremental prefix matches a fresh parse including open fences and tables', () => {
  const source = '# 标题\r\n\r\n```kotlin\n  val x = 1\n\n  print(x)\n```\n\n| 店 | 额 |\n| --- | --- |\n| A | 0 |\n\n> 引用\n\n结束';
  for (const size of [1, 2, 7, 13]) {
    const cache = new MarkdownBlockCache();
    for (let end = 1; end <= source.length; end += size) {
      const prefix = source.slice(0, end);
      cache.update(prefix, true);
      assert.deepEqual(cache.blocks, markdown(prefix), `chunk size ${size}, end ${end}`);
    }
    cache.update(source, false); assert.deepEqual(cache.blocks, markdown(source));
  }
});
test('Markdown cache: replacements, truncation and stream restart reset committed content', () => {
  const cache = new MarkdownBlockCache();
  for (const [value, streaming] of [['第一段\n\n第二段', true], ['新的回复', true], ['', true], ['final\n\ntext', false], ['next\n\ntail', true], ['next\n\ntail', false], ['', false]]) {
    cache.update(value, streaming); assert.deepEqual(cache.blocks, markdown(value));
  }
});
test('export: overview exports raw store and channel fields with selected scope', () => {
  const rows = analyticsExportRows('经营总览', range, '南店', { overview: { stores: [{ store_label: '南店', metrics: { order_count: { current: 0 }, net_income: { current: 1234.567 } } }], channels: [{ dim_label: '堂食', metrics: { avg_order_value: { current: 12.5 } } }] } });
  assert.deepEqual(rows.slice(0, 5), [['模块', '经营总览'], ['开始日期', range.date_from], ['结束日期', range.date_to], ['门店范围', '南店'], []]);
  assert.deepEqual(rows[6], ['南店', '0', '1234.567', '']);
  assert.deepEqual(rows.at(-1), ['堂食', '', '', '12.5']);
});
test('export: products preserve all six iOS fields including both shares and orders', () => {
  const rows = analyticsExportRows('产品', range, '全部门店', { products: { items: [{ product_name: 'A', quantity: 0, sales_amount: 12.3, order_count: 2, quantity_share: .1, amount_share: .2 }] } });
  assert.equal(rows[5].length, 6); assert.deepEqual(rows[6], ['A', '0', '12.3', '2', '0.1', '0.2']);
});
test('export: labor preserves planned versus actual hours and hourly output', () => {
  const rows = analyticsExportRows('人效', range, '南店', { labor: { points: [{ period: '2026-09-01', actual_hours: 0, planned_hours: 8, net_revenue: 400, headcount: 2, planned_revenue_per_hour: 50 }] } });
  assert.equal(rows[5].length, 7); assert.deepEqual(rows[6], ['2026-09-01', '0', '8', '400', '2', '', '50']);
});
test('export: alerts retain baseline, direction, status and all reason hints', () => {
  const rows = analyticsExportRows('报警', range, '南店', { alerts: [{ business_date: '2026-09-30', shop_key: 's1', actual_amount: 20, baseline_amount: 40, deviation_pct: -50, direction: 'down', status: 'active', reason_hints: ['原因1', '原因2'] }] });
  assert.equal(rows[5].length, 8); assert.deepEqual(rows[6], ['2026-09-30', 's1', '20', '40', '-50', 'down', 'active', '原因1；原因2']);
});
test('detail: store/channel include orders, net revenue, average order and refunds', () => {
  const detail = dimensionDetail({ dim_key: 'channel', metrics: { refund_amount: { current: 0 } } }, '渠道分布');
  assert.equal(detail.title, 'channel'); assert.equal(detail.rows.length, 4);
  assert.equal(detail.rows[0][1], '—'); assert.equal(detail.rows[3][1], '¥0');
});
test('detail: labor includes six metrics and alert includes reasons', () => {
  const labor = laborDetail({ period: '2026-09-30', actual_hours: 0 });
  assert.equal(labor.title, '2026-09-30'); assert.equal(labor.rows.length, 6); assert.equal(labor.rows[0][1], '0');
  const alert = alertDetail({ business_date: '2026-09-30', shop_key: 's1', actual_amount: 0, baseline_amount: 20, deviation_pct: -100, status: 'active', reason_hints: ['reason1', 'reason2'] });
  assert.equal(alert.title, 's1'); assert.ok(alert.rows.some(row => row[1].includes('reason1') && row[1].includes('reason2')));
});
