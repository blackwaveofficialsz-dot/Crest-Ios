const test = require('node:test');
const assert = require('node:assert/strict');
const { markdown, inline } = require('../work/test-core/Markdown');
const { analyticsRange } = require('../work/test-core/Dates');
const { periodQuery, recentTrend, validRange, storeOptions, csv, numberText } = require('../work/test-core/Analytics');
const { visibleColumns, formatMetric, formatTableValue, metricRows, tableRows, tableWidths, responseStatus } = require('../work/test-core/ResponseFormat');
test('AGUI: metrics match currency, ratio, count and unknown-unit formatting', () => {
  assert.equal(formatMetric({ key: 'income', value: '1234.5', unit: 'cny' }), '¥1,234.5');
  assert.equal(formatMetric({ key: 'rate', value: '.123456', unit: 'ratio' }), '12.3456%');
  assert.equal(formatMetric({ key: 'count', value: '3', unit: 'order' }), '3单');
  assert.equal(formatMetric({ key: 'weight', value: '2', unit: 'kg' }), '2 kg');
  assert.equal(formatMetric({ key: 'missing', value: '—', unit: 'cny' }), '—');
});
test('AGUI: empty columns hidden, technical columns moved last, zero preserved', () => {
  const part = { columns: [{ key: 'shop_id', label: 'shop_id' }, { key: 'empty', label: '空' }, { key: 'amount', label: '金额', data_type: 'decimal', unit: 'cny' }], preview_rows: [{ shop_id: 's1', empty: null, amount: 0 }] };
  assert.deepEqual(visibleColumns(part).map(x => x.key), ['amount', 'shop_id']);
  assert.deepEqual(tableRows(part), [['¥0', 's1']]);
});
test('AGUI: table handles comparison status and missing/non-numeric values', () => {
  assert.equal(formatTableValue('not_comparable', { key: 'comparison_status' }), '不可比');
  assert.equal(formatTableValue(null, { key: 'amount', data_type: 'decimal' }), '—');
  assert.equal(formatTableValue('', { key: 'amount', data_type: 'decimal' }), '');
  assert.equal(formatTableValue('abc', { key: 'amount', data_type: 'decimal' }), 'abc');
  assert.equal(formatTableValue('1.25', { key: 'hours', data_type: 'decimal', unit: 'hour' }), '1.25小时');
});
test('AGUI: metric layout has two columns without dropping odd last card', () => {
  const metrics = [1, 2, 3].map(n => ({ key: String(n), value: String(n) }));
  assert.deepEqual(metricRows(metrics).map(row => row.length), [2, 1]);
});
test('Markdown: headings, paragraphs, lists, quote and divider', () => {
  const parsed = markdown('# 标题\n\n内容 **强调**\n\n- 甲\n- 乙\n\n3. 三\n4. 四\n\n> 引用\n> 第二行\n\n---');
  assert.deepEqual(parsed.map(x => x.kind), ['heading', 'paragraph', 'list', 'ordered', 'quote', 'divider']);
  assert.equal(parsed[0].level, 1); assert.equal(parsed[3].start, 3); assert.equal(parsed[4].text, '引用\n第二行');
});
test('Markdown: incomplete streamed code fence preserves whitespace', () => {
  const parsed = markdown('```kotlin\n  val x = 1\n  println(x)');
  assert.equal(parsed[0].language, 'kotlin'); assert.equal(parsed[0].text, '  val x = 1\n  println(x)');
});
test('Markdown: tables have independent headers and incomplete rows', () => {
  const parsed = markdown('| 门店 | 金额 |\n| :--- | ---: |\n| A | 12 |\n| B |\n\n结束');
  assert.equal(parsed[0].kind, 'table'); assert.deepEqual(parsed[0].headers, ['门店', '金额']);
  assert.deepEqual(parsed[0].rows[0], ['A', '12']);
});
test('Markdown: inline styles, code, strike and links', () => {
  const parts = inline('**粗体** *斜体* `代码` ~~删除~~ [链接](https://example.org)');
  assert.ok(parts.some(p => p.bold && p.text === '粗体')); assert.ok(parts.some(p => p.italic && p.text === '斜体'));
  assert.ok(parts.some(p => p.code && p.text === '代码')); assert.ok(parts.some(p => p.strike && p.text === '删除'));
  assert.ok(parts.some(p => p.link === 'https://example.org'));
});
test('Markdown: HTML stays literal text instead of executable content', () => {
  assert.equal(markdown('<script>alert(1)</script>')[0].text, '<script>alert(1)</script>');
});
test('dates: China business date does not depend on host timezone', () => {
  const now = Date.parse('2026-10-02T16:15:00Z');
  assert.deepEqual(analyticsRange(0, now), { date_from: '2026-10-02', date_to: '2026-10-02' });
  assert.deepEqual(analyticsRange(1, now), { date_from: '2026-09-26', date_to: '2026-10-02' });
  assert.deepEqual(analyticsRange(2, now), { date_from: '2026-10-01', date_to: '2026-10-02' });
  assert.deepEqual(analyticsRange(3, now), { date_from: '2026-09-01', date_to: '2026-09-30' });
});
test('dates: previous month handles leap day and year boundary', () => {
  assert.deepEqual(analyticsRange(2, Date.parse('2024-03-01T10:00:00Z')), { date_from: '2024-02-01', date_to: '2024-02-29' });
  assert.deepEqual(analyticsRange(3, Date.parse('2024-03-01T10:00:00Z')), { date_from: '2024-01-01', date_to: '2024-01-31' });
  assert.deepEqual(analyticsRange(3, Date.parse('2026-01-01T10:00:00Z')), { date_from: '2025-11-01', date_to: '2025-11-30' });
});
test('dates: iOS custom filter cannot include today or the future', () => {
  const now = Date.parse('2026-10-02T16:15:00Z');
  assert.equal(validRange('2026-10-01', '2026-10-02', now), true);
  assert.equal(validRange('2026-10-01', '2026-10-03', now), false);
});
test('AGUI: iOS result status labels and dynamic column widths', () => {
  assert.equal(responseStatus('ok'), ''); assert.equal(responseStatus('partial'), '结果不完整');
  assert.equal(responseStatus('empty'), '暂无数据'); assert.equal(responseStatus('unavailable'), '数据暂不可用');
  assert.equal(responseStatus('unknown'), '结果状态未知');
  assert.deepEqual(tableWidths({ columns: [{ key: 'name', label: '门店' }, { key: 'amount', label: '金额', data_type: 'decimal' }, { key: 'shop_id', label: 'shop_id' }], preview_rows: [{ name: '南店', amount: 1, shop_id: 'a' }] }), [144, 112, 180]);
});
test('trend: last 30 completed days, excludes today', () => {
  assert.deepEqual(recentTrend(Date.parse('2026-10-02T16:15:00Z')), { date_from: '2026-09-03', date_to: '2026-10-02' });
});
test('filter: rejects impossible or reversed dates', () => {
  assert.ok(validRange('2024-02-29', '2024-03-01')); assert.equal(validRange('2025-02-29', '2025-03-01'), false);
  assert.equal(validRange('2026-10-04', '2026-10-03'), false); assert.equal(validRange('x', 'x'), false);
});
test('analytics: repeated store_keys preserved and safely encoded', () => {
  assert.equal(periodQuery({ date_from: '2026-01-01', date_to: '2026-01-02' }, ['a+b', '东店&1']), 'date_from=2026-01-01&date_to=2026-01-02&store_keys=a%2Bb&store_keys=%E4%B8%9C%E5%BA%97%261');
});
test('analytics: nested scope flattened and duplicate stores removed', () => {
  const options = storeOptions([{ key: 'group', label: '组', type: 'group', children: [{ key: 'x', type: 'shop', store_key: 's', label: '门店' }] }, { key: 'y', type: 'shop', store_key: 's', label: '重复' }]);
  assert.deepEqual(options, [{ key: 's', label: '门店' }]);
});
test('CSV: UTF8 BOM, quotes, multiline and formula protection', () => {
  const result = csv([['名字', '值'], ['A"B', 'a\nb'], ['=CMD()', '  @SUM(1)']]);
  assert.ok(result.startsWith('\uFEFF')); assert.ok(result.includes('"A""B"')); assert.ok(result.includes('"\'=CMD()"')); assert.ok(result.includes('"\'  @SUM(1)"'));
});
test('analytics: missing values distinguished from zero', () => {
  assert.equal(numberText(undefined), '—'); assert.equal(numberText(null), '—'); assert.equal(numberText(0), '0');
  assert.equal(numberText(NaN), '—'); assert.ok(numberText(12, true).startsWith('¥'));
});
