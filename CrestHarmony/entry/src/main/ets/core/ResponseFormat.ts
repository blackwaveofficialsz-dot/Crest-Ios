import { Cell, CellObject, ResponseColumn, ResponseMetric, ResponsePart } from './Models';
import { localizedFormat, translate } from './Localization';

export function displayCell(value: Cell | undefined): string {
  if (value === null || value === undefined) return '—';
  if (Array.isArray(value)) return value.map((item: Cell) => displayCell(item)).join(', ');
  if (typeof value === 'object') {
    const record = value as CellObject;
    return Object.keys(record).sort().map((key: string) => key + ': ' + displayCell(record[key])).join(', ');
  }
  return String(value);
}
export function visibleColumns(part: ResponsePart): ResponseColumn[] {
  const columns = (part.columns || []).filter((column: ResponseColumn) =>
    (part.preview_rows || []).some((row: Record<string, Cell>) => {
      const value = displayCell(row[column.key]).trim(); return value !== '' && value !== '—';
    }));
  const technical = (column: ResponseColumn): boolean => column.label.includes('_') ||
    (column.label === column.key && /^[\x00-\x7F]*$/.test(column.label));
  return columns.filter((column: ResponseColumn) => !technical(column)).concat(columns.filter(technical));
}
function formatNumber(value: number): string {
  return value.toLocaleString('zh-CN', { maximumFractionDigits: 4 });
}
function withUnit(value: number, unit: string | undefined, unknownUnit: boolean, locale: string): string {
  const formatted = formatNumber(value);
  switch (unit?.toLowerCase()) {
    case 'cny': return '¥' + formatted;
    case 'ratio': return formatNumber(value * 100) + '%';
    case 'order': return localizedFormat('%@单', locale, [formatted]);
    case 'store': return localizedFormat('%@家', locale, [formatted]);
    case 'hour': return localizedFormat('%@小时', locale, [formatted]);
    case 'period': return localizedFormat('%@期', locale, [formatted]);
    case 'product': return localizedFormat('%@种', locale, [formatted]);
    case 'item': return localizedFormat('%@件', locale, [formatted]);
    case 'person': return localizedFormat('%@人', locale, [formatted]);
    default: return formatted + (unknownUnit && unit ? ' ' + unit : '');
  }
}
function numeric(value: string): boolean {
  return /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/.test(value) && Number.isFinite(Number(value));
}
export function formatMetric(metric: ResponseMetric, locale: string = 'zh-Hans'): string {
  const value = String(metric.value);
  return numeric(value) ? withUnit(Number(value), metric.unit, true, locale) : value;
}
export function formatTableValue(value: Cell | undefined, column: ResponseColumn, locale: string = 'zh-Hans'): string {
  const text = displayCell(value);
  if (text === '—') return text;
  if (column.key === 'comparison_status') return translate(text === 'comparable' ? '可比' : text === 'not_comparable' ? '不可比' : '未知', locale);
  return (column.data_type === 'decimal' || column.data_type === 'integer') && numeric(text) ? withUnit(Number(text), column.unit, false, locale) : text;
}
export function metricRows(metrics: ResponseMetric[]): ResponseMetric[][] {
  const rows: ResponseMetric[][] = [];
  for (let index = 0; index < metrics.length; index += 2) rows.push(metrics.slice(index, index + 2));
  return rows;
}
export function tableHeaders(part: ResponsePart): string[] { return visibleColumns(part).map((column: ResponseColumn) => column.label); }
export function tableRows(part: ResponsePart, locale: string = 'zh-Hans'): string[][] {
  const columns = visibleColumns(part);
  return (part.preview_rows || []).map((row: Record<string, Cell>) => columns.map((column: ResponseColumn) => formatTableValue(row[column.key], column, locale)));
}
export function tableWidths(part: ResponsePart): number[] {
  return visibleColumns(part).map((column: ResponseColumn) => {
    if (column.data_type === 'decimal' || column.data_type === 'integer') return 112;
    const longest = Math.max(column.label.length, ...(part.preview_rows || []).map((row: Record<string, Cell>) => displayCell(row[column.key]).length));
    const technical = column.label.includes('_') || (column.label === column.key && /^[\x00-\x7F]*$/.test(column.label));
    return longest > 18 ? 220 : longest > 10 || technical ? 180 : 144;
  });
}
export function responseStatus(status: string): string {
  switch (status) {
    case 'ok': case 'cancelled': case '': return '';
    case 'partial': return '结果不完整';
    case 'empty': return '暂无数据';
    case 'unavailable': return '数据暂不可用';
    case 'failed': return '分析失败';
    default: return '结果状态未知';
  }
}
