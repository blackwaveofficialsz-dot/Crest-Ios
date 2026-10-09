import type { DateRange, Overview, Dimension } from './Models';
import { analyticsRange } from './Dates';
export interface StoreNode { key: string; type: string; label: string; store_key?: string; children?: StoreNode[] }
export interface StoreScope { nodes: StoreNode[]; store_count: number }
export interface StoreOption { key: string; label: string }
export interface RevenuePoint { period: string; net_income: number; order_count: number; missing?: boolean }
export interface RevenueTrend { points: RevenuePoint[] }
export interface Product { product_key: string; product_name: string; quantity: number; sales_amount: number; order_count?: number; quantity_share: number; amount_share: number }
export interface Products { data_status: string; items: Product[]; total: number }
export interface ProductPoint { period: string; quantity: number; sales_amount: number; missing?: boolean }
export interface ProductTrend { product_key: string; product_name?: string; points: ProductPoint[] }
export interface LaborSummary { actual_hours: number; planned_hours: number; net_revenue: number; headcount: number; actual_revenue_per_hour?: number; planned_revenue_per_hour?: number }
export interface LaborPoint extends LaborSummary { period: string; data_status: string }
export interface Labor { data_status: string; points: LaborPoint[]; summary: LaborSummary }
export interface RevenueAlert { actual_amount: number; baseline_amount: number; business_date: string; deviation_pct: number; direction: string; reason_hints?: string[]; shop_key: string; shop_label?: string; status: string }
export interface RevenueAlerts { alerts: RevenueAlert[] }
export interface ChartPoint { label: string; value?: number; comparison?: number }
export interface AnalyticsDetail { title: string; subtitle: string; rows: string[][] }
export interface AnalyticsExport { overview?: Overview; products?: Products; labor?: Labor; alerts?: RevenueAlert[] }
export function dimensionDetail(item: Dimension, subtitle: string): AnalyticsDetail {
  return { title: item.store_label || item.dim_label || item.store_key || item.dim_key || '—', subtitle: subtitle,
    rows: [['订单数', numberText(item.metrics['order_count']?.current)], ['净实收', numberText(item.metrics['net_income']?.current, true)],
      ['客单价', numberText(item.metrics['avg_order_value']?.current, true)], ['退款金额', numberText(item.metrics['refund_amount']?.current, true)]] };
}
export function laborDetail(item: LaborPoint): AnalyticsDetail {
  return { title: item.period, subtitle: '人效日明细', rows: [['实际工时', numberText(item.actual_hours)], ['计划工时', numberText(item.planned_hours)],
    ['净营收', numberText(item.net_revenue, true)], ['人数', numberText(item.headcount)],
    ['实际小时产出', numberText(item.actual_revenue_per_hour, true)], ['计划小时产出', numberText(item.planned_revenue_per_hour, true)]] };
}
export function alertDetail(item: RevenueAlert): AnalyticsDetail {
  const rows = [['实际营收', numberText(item.actual_amount, true)], ['基准营收', numberText(item.baseline_amount, true)],
    ['偏离率', (item.deviation_pct > 0 ? '+' : '') + item.deviation_pct.toFixed(1) + '%'], ['状态', item.status]];
  if (item.reason_hints?.length) rows.push(['原因提示', item.reason_hints.join('；')]);
  return { title: item.shop_label || item.shop_key, subtitle: item.business_date, rows: rows };
}
// Same export columns and scope as BusinessAnalyticsView.makeExportDocument; no UI-formatted numbers.
export function analyticsExportRows(title: string, range: DateRange, storeSummary: string, data: AnalyticsExport): string[][] {
  const raw = (value: number | undefined): string => value === undefined || value === null ? '' : String(value);
  const rows: string[][] = [['模块', title], ['开始日期', range.date_from], ['结束日期', range.date_to], ['门店范围', storeSummary], []];
  if (data.overview) {
    rows.push(['门店', '订单数', '净实收', '客单价']);
    data.overview.stores.forEach((item: Dimension) => rows.push([item.store_label || item.dim_label || item.store_key || item.dim_key || '', raw(item.metrics['order_count']?.current), raw(item.metrics['net_income']?.current), raw(item.metrics['avg_order_value']?.current)]));
    rows.push([], ['渠道', '订单数', '净实收', '客单价']);
    data.overview.channels.forEach((item: Dimension) => rows.push([item.dim_label || item.dim_key || '', raw(item.metrics['order_count']?.current), raw(item.metrics['net_income']?.current), raw(item.metrics['avg_order_value']?.current)]));
  } else if (data.products) {
    rows.push(['产品', '销量', '销售额', '订单数', '数量占比', '销售额占比']);
    data.products.items.forEach((item: Product) => rows.push([item.product_name, raw(item.quantity), raw(item.sales_amount), raw(item.order_count), raw(item.quantity_share), raw(item.amount_share)]));
  } else if (data.labor) {
    rows.push(['日期', '实际工时', '计划工时', '净营收', '人数', '实际小时产出', '计划小时产出']);
    data.labor.points.forEach((item: LaborPoint) => rows.push([item.period, raw(item.actual_hours), raw(item.planned_hours), raw(item.net_revenue), raw(item.headcount), raw(item.actual_revenue_per_hour), raw(item.planned_revenue_per_hour)]));
  } else if (data.alerts) {
    rows.push(['业务日期', '门店', '实际营收', '基准营收', '偏离率', '方向', '状态', '原因提示']);
    data.alerts.forEach((item: RevenueAlert) => rows.push([item.business_date, item.shop_label || item.shop_key, raw(item.actual_amount), raw(item.baseline_amount), raw(item.deviation_pct), item.direction, item.status, (item.reason_hints || []).join('；')]));
  }
  return rows;
}
export function storeOptions(nodes: StoreNode[]): StoreOption[] {
  const output: StoreOption[] = [];
  const visit = (items: StoreNode[]): void => {
    items.forEach(item => { if (item.store_key && !output.some(old => old.key === item.store_key)) output.push({ key: item.store_key, label: item.label }); visit(item.children || []); });
  };
  visit(nodes); return output.sort((a, b) => a.label.localeCompare(b.label));
}
export function periodQuery(range: DateRange, keys: string[]): string {
  return `date_from=${encodeURIComponent(range.date_from)}&date_to=${encodeURIComponent(range.date_to)}` +
    keys.map(key => `&store_keys=${encodeURIComponent(key)}`).join('');
}
export function recentTrend(now: number = Date.now()): DateRange {
  const end = new Date(now + 8 * 3600000 - 86400000).toISOString().slice(0, 10);
  return { date_from: new Date(Date.parse(end) - 29 * 86400000).toISOString().slice(0, 10), date_to: end };
}
export function validRange(from: string, to: string, now: number = Date.now()): boolean {
  const valid = (date: string): boolean => /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(Date.parse(date)) && new Date(date).toISOString().slice(0, 10) === date;
  return valid(from) && valid(to) && from <= to && to <= analyticsRange(0, now).date_to;
}
export function numberText(value?: number, money: boolean = false): string {
  if (value === undefined || value === null || !Number.isFinite(value)) return '—';
  return (money ? '¥' : '') + value.toLocaleString('zh-CN', { maximumFractionDigits: money ? 2 : 1 });
}
// Protect exports from spreadsheet formula interpretation, including leading whitespace.
export function csv(rows: string[][]): string {
  return '\uFEFF' + rows.map(row => row.map(value => {
    const safe = /^[\s]*[=+\-@]/.test(value) ? "'" + value : value;
    return '"' + safe.replace(/"/g, '""') + '"';
  }).join(',')).join('\r\n');
}
