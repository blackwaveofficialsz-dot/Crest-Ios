import type { AgentResponse, ChatMessage, HistoryMessage, ResponseAction, ResponsePart, RunBody, WireEvent, Interaction } from './Models';
import { ChatMessage as Message } from './Models';

// Only versioned, actionable parts are presented. Legacy / future payloads keep their plain-text fallback.
export function supportedParts(response?: AgentResponse): ResponsePart[] {
  if (!response || response.version !== 1 || typeof response.source_turn_id !== 'string' || !response.source_turn_id.trim() || !Array.isArray(response.parts)) return [];
  return response.parts.slice(0, 6).filter((p: ResponsePart) => {
    if (!p) return false;
    if (p.kind === 'table') return Array.isArray(p.columns) && p.columns.length > 0 && p.columns.every(c => c && typeof c.key === 'string' && typeof c.label === 'string') && (!p.preview_rows || (Array.isArray(p.preview_rows) && p.preview_rows.every(row => row && typeof row === 'object')));
    if (p.kind === 'summary') return nonempty(p.message) || (Array.isArray(p.metrics) && p.metrics.length > 0 && p.metrics.every(m => m && typeof m.key === 'string' && typeof m.value === 'string'));
    if (p.kind === 'insights') return Array.isArray(p.items) && p.items.length > 0 && p.items.every(item => item && typeof item.text === 'string');
    if (p.kind === 'notice') return nonempty(p.message) && ['info', 'warning', 'error'].includes(p.severity || '');
    return p.kind === 'clarification' && nonempty(p.message);
  });
}
export function supportedActions(response?: AgentResponse): ResponseAction[] {
  if (!response || response.version !== 1 || !nonempty(response.source_turn_id) || !Array.isArray(response.actions)) return [];
  return response.actions.slice(0, 6).filter((a: ResponseAction) => !!a && nonempty(a.action_id) && nonempty(a.label) &&
    nonempty(a.params?.message) && a.source_turn_id === response.source_turn_id &&
    (a.kind === 'prompt' || (a.kind === 'clarify' && nonempty(a.params?.candidate_id))));
}
function nonempty(value?: string): boolean { return typeof value === 'string' && !!value.trim(); }
export function historyMessage(item: HistoryMessage): ChatMessage[] {
  if (!['user', 'assistant'].includes(item.role)) return [];
  const message = new Message(item.id, item.role, item.content || '');
  try {
    message.parts = supportedParts(item.metadata?.agent_response);
    message.actions = supportedActions(item.metadata?.agent_response);
    message.status = item.metadata?.agent_response?.result_status || item.metadata?.delivery_status || '';
  } catch (_) { /* Malformed legacy metadata must not hide the conversation. */ }
  if (item.metadata?.delivery_status === 'failed') message.error = item.content || '回复失败';
  return [message];
}
export function runBody(thread: string, run: string, messageId: string, text: string, cursor: string = '', interaction?: Interaction): RunBody {
  const forwarded: { afterEventId?: string; interaction?: Interaction } = {};
  if (cursor) forwarded.afterEventId = cursor;
  if (interaction) forwarded.interaction = interaction;
  return { threadId: thread, runId: run, parentRunId: null, state: {},
    messages: [{ id: messageId, role: 'user', content: text }], tools: [], context: [], forwardedProps: forwarded };
}
export interface Frame { id: string; data: string }
export class SSEDecoder {
  private pending: string = ''; private id: string = ''; private lines: string[] = []; private frameSize: number = 0;
  constructor(private emit: (frame: Frame) => void) {}
  feed(text: string): void {
    this.pending += text;
    if (this.pending.length > 2 * 1024 * 1024) throw new Error('回复事件过大');
    let end = this.pending.indexOf('\n');
    while (end >= 0) {
      const line = this.pending.slice(0, end).replace(/\r$/, '');
      this.pending = this.pending.slice(end + 1);
      this.line(line); end = this.pending.indexOf('\n');
    }
  }
  finish(): void { if (this.pending) this.line(this.pending.replace(/\r$/, '')); this.pending = ''; this.flush(); }
  private line(line: string): void {
    if (!line) this.flush();
    else if (line.startsWith('id:')) { if (this.lines.length) this.flush(); this.id = line.slice(3).trim(); }
    else if (line.startsWith('data:')) {
      this.frameSize += line.length;
      if (this.frameSize > 2 * 1024 * 1024) throw new Error('回复事件过大');
      this.lines.push(line.slice(5).replace(/^ /, ''));
    }
  }
  private flush(): void {
    if (this.lines.length) this.emit({ id: this.id, data: this.lines.join('\n') });
    this.id = ''; this.lines = []; this.frameSize = 0;
  }
}
export class EventValidator {
  private seen: Set<string> = new Set(); private textId: string = '';
  constructor(private thread: string, private run: string) {}
  parse(frame: Frame): WireEvent | undefined {
    const e = JSON.parse(frame.data) as WireEvent;
    if (!e || !e.type || !e.eventId || !Number.isInteger(e.sequence) || e.runId !== this.run || e.threadId !== this.thread)
      throw new Error('对话事件协议不匹配');
    const parts = e.eventId.split(':');
    if (parts.length !== 3 || parts[0] !== this.run || parts[1] !== String(e.sequence) || !/^-?\d+$/.test(parts[2]) || frame.id !== e.eventId)
      throw new Error('对话事件游标不匹配');
    if (this.seen.has(e.eventId)) return undefined;
    if (e.type === 'TEXT_MESSAGE_START') {
      if (!e.messageId || e.role !== 'assistant') throw new Error('回复消息格式不匹配');
      this.textId = e.messageId;
    }
    if (e.type === 'TEXT_MESSAGE_CONTENT' && (!this.textId || e.messageId !== this.textId || typeof e.delta !== 'string'))
      throw new Error('回复片段无法关联到当前消息');
    this.seen.add(e.eventId);
    return e;
  }
}
export function validPassword(value: string): boolean { return value.length >= 7 && value.length <= 16; }
export function validPhone(value: string): boolean { return /^1\d{10}$/.test(value); }
export function safeLink(url: string): boolean { return /^https?:\/\//i.test(url); }
export function cropRegion(width: number, height: number, zoom: number, x: number, y: number, viewport: number): number[] {
  const side = Math.max(1, Math.min(width, height) / Math.max(1, Math.min(4, zoom)));
  const pixelsPerPoint = side / viewport;
  return [Math.round(Math.max(0, Math.min(width - side, (width - side) / 2 - x * pixelsPerPoint))),
    Math.round(Math.max(0, Math.min(height - side, (height - side) / 2 - y * pixelsPerPoint))), Math.floor(side)];
}
// EXIF mirror is applied before clockwise rotation. ImageSource returns these names on API 12.
export function avatarOrientation(value: string): number[] {
  switch (value) {
    case '2': case 'Top-right': return [0, 1, 0];
    case '3': case 'Bottom-right': return [180, 0, 0];
    case '4': case 'Bottom-left': return [0, 0, 1];
    case '5': case 'Left-top': return [270, 1, 0];
    case '6': case 'Right-top': return [90, 0, 0];
    case '7': case 'Right-bottom': return [90, 1, 0];
    case '8': case 'Left-bottom': return [270, 0, 0];
    default: return [0, 0, 0];
  }
}
