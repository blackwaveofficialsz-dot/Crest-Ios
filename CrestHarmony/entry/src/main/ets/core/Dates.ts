import type { DateRange } from './Models';
// The backend/iOS business calendar is Asia/Shanghai, independent of the device time zone.
export function analyticsRange(period: number, now: number = Date.now()): DateRange {
  const local = new Date(now + 8 * 3600000);
  const yesterday = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - 86400000;
  // iOS anchors every preset to the last completed business day, including month boundaries.
  const anchor = new Date(yesterday), year = anchor.getUTCFullYear(), month = anchor.getUTCMonth();
  const start = period === 0 ? yesterday : period === 1 ? yesterday - 6 * 86400000 : period === 3 ? Date.UTC(year, month - 1, 1) : Date.UTC(year, month, 1);
  const end = period === 3 ? Date.UTC(year, month, 0) : yesterday;
  return { date_from: new Date(start).toISOString().slice(0, 10), date_to: new Date(end).toISOString().slice(0, 10) };
}
