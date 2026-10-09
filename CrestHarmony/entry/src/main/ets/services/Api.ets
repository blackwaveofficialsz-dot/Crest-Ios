import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { WireEvent, Interaction } from '../core/Models';
import { EventValidator, SSEDecoder, Frame, runBody } from '../core/Protocol';

export const API_BASE = 'https://blackwave.org.cn/yuanji';
export const AUTH = '/api/v1/auth/';
export function body(fields: Record<string, string | boolean | null>): string { return JSON.stringify(fields); }
export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}
interface ErrorDetail { detail?: string }
function responseError(status: number, text: string): ApiError {
  let message = status === 401 ? '登录已失效，请重新登录' : `请求失败（${status}）`;
  try { const payload = JSON.parse(text) as ErrorDetail; if (typeof payload.detail === 'string') message = payload.detail; } catch (_) {}
  return new ApiError(status, message);
}
export function errorText(error: Error): string {
  return error instanceof ApiError ? error.message : '操作未完成，请检查网络后重试';
}
export class RunRequest {
  thread: string = ''; run: string = ''; messageId: string = ''; text: string = ''; cursor: string = '';
  interaction?: Interaction;
  validator?: EventValidator;
}
export class StreamControl {
  cancelled: boolean = false;
  request?: http.HttpRequest;
  onCancel: () => void = () => {};
  cancel(): void { this.cancelled = true; this.onCancel(); this.request?.destroy(); this.request = undefined; }
}
export class Api {
  async call<T>(method: http.RequestMethod | 'PATCH', path: string, payload: string = '', token: string = ''): Promise<T> {
    // rcp supports PATCH on API 12; NetworkKit's PATCH enum requires API 26.
    const session = rcp.createSession();
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    if (payload) headers['Content-Type'] = 'application/json';
    if (token) headers['Authorization'] = `Bearer ${token}`;
    try {
      const request = new rcp.Request(API_BASE + path, method, headers, payload || undefined);
      request.configuration = { transfer: { autoRedirect: false, timeout: { connectMs: 20000, transferMs: 60000 } } };
      const result = await session.fetch(request);
      const text = result.toString() || '';
      if (result.statusCode < 200 || result.statusCode >= 300) throw responseError(result.statusCode, text);
      return JSON.parse(text || '{}') as T;
    } finally { session.close(); }
  }
  async avatar(token: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const result = await request.request(API_BASE + AUTH + 'profile/avatar', {
        header: { 'Authorization': `Bearer ${token}` }, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000, readTimeout: 30000, usingCache: false
      });
      if (result.responseCode !== 200) throw responseError(result.responseCode, '');
      return result.result as ArrayBuffer;
    } finally { request.destroy(); }
  }
  async uploadAvatar(data: ArrayBuffer, token: string): Promise<void> {
    if (!data.byteLength || data.byteLength > 1024 * 1024) throw new ApiError(0, '头像不能超过 1 MB');
    const boundary = `Crest-${util.generateRandomUUID()}`;
    const encoder = new util.TextEncoder();
    const prefix = encoder.encodeInto(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="avatar.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`);
    const suffix = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const bytes = new Uint8Array(prefix.length + data.byteLength + suffix.length);
    bytes.set(prefix); bytes.set(new Uint8Array(data), prefix.length); bytes.set(suffix, prefix.length + data.byteLength);
    const request = http.createHttp();
    try {
      const result = await request.request(API_BASE + AUTH + 'profile/avatar', {
        method: http.RequestMethod.PUT,
        header: { 'Authorization': `Bearer ${token}`, 'Content-Type': `multipart/form-data; boundary=${boundary}` },
        extraData: bytes.buffer, connectTimeout: 20000, readTimeout: 60000, usingCache: false
      });
      if (result.responseCode < 200 || result.responseCode >= 300) throw responseError(result.responseCode, result.result as string);
    } finally { request.destroy(); }
  }
  async stream(run: RunRequest, token: string, control: StreamControl, receive: (event: WireEvent) => void): Promise<void> {
    if (!run.validator) run.validator = new EventValidator(run.thread, run.run);
    const validator = run.validator;
    for (let attempt = 0; attempt < 3; attempt++) {
      if (control.cancelled) return;
      const request = http.createHttp(); control.request = request;
      let terminal = false; let parseError: Error | undefined;
      let contentType = ''; let hasHeaders = false; let rawError = '';
      let finishData: () => void = () => {};
      const dataEnd = new Promise<void>((resolve) => { finishData = resolve; });
      control.onCancel = finishData;
      request.on('dataEnd', () => finishData());
      const utf8 = util.TextDecoder.create('utf-8');
      const decoder = new SSEDecoder((frame: Frame) => {
        if (terminal || control.cancelled) return;
        const event = validator.parse(frame);
        if (!event) return;
        run.cursor = event.eventId;
        receive(event);
        terminal = event.type === 'RUN_FINISHED' || event.type === 'RUN_ERROR' ||
          (event.type === 'STATE_SNAPSHOT' && !!event.snapshot?.approval_id);
      });
      request.on('headersReceive', (headers: Object) => {
        const fields = headers as Record<string, string>;
        contentType = (fields['content-type'] || fields['Content-Type'] || '').toLowerCase(); hasHeaders = true;
      });
      request.on('dataReceive', (buffer: ArrayBuffer) => {
        if (control.cancelled || parseError) return;
        try {
          const text = utf8.decodeToString(new Uint8Array(buffer), { stream: true });
          if (hasHeaders && !contentType.includes('text/event-stream')) rawError = (rawError + text).slice(0, 65536);
          else decoder.feed(text);
        } catch (error) { parseError = error as Error; }
      });
      const headers: Record<string, string> = {
        'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'Accept': 'text/event-stream'
      };
      if (run.cursor) headers['Last-Event-ID'] = run.cursor;
      try {
        const status = await request.requestInStream(API_BASE + '/api/v1/agui/runs', {
          method: http.RequestMethod.POST, header: headers,
          extraData: JSON.stringify(runBody(run.thread, run.run, run.messageId, run.text, run.cursor, run.interaction)),
          connectTimeout: 20000, readTimeout: 120000, usingCache: false
        });
        if (control.cancelled) return;
        if (status < 200 || status >= 300) throw responseError(status, rawError);
        await dataEnd;
        if (control.cancelled) return;
        if (hasHeaders && !contentType.includes('text/event-stream')) throw new ApiError(0, '服务器未返回流式对话数据');
        if (parseError) throw new ApiError(0, parseError.message);
        decoder.feed(utf8.decodeToString(new Uint8Array(0), { stream: false })); decoder.finish();
        if (terminal) return;
      } catch (error) {
        if (control.cancelled) return;
        if (terminal && !parseError) return;
        if (error instanceof ApiError || attempt === 2) throw error as Error;
      } finally { request.destroy(); if (control.request === request) { control.request = undefined; control.onCancel = () => {}; } }
      await new Promise<void>((resolve) => { setTimeout(resolve, attempt === 0 ? 300 : 700); });
    }
    throw new ApiError(0, '回复中断，请重试');
  }
}
