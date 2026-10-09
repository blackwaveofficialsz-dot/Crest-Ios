import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Session } from '../services/Session';
import { ApiError, RunRequest, StreamControl, body, errorText } from '../services/Api';
import { ChatMessage, Conversation, ConversationDetail, ResponseAction, Interaction, WireEvent } from '../core/Models';
import { historyMessage, supportedParts, supportedActions } from '../core/Protocol';

@Observed
export class ChatStore {
  messages: ChatMessage[] = []; sessions: Conversation[] = [];
  activeId: string = ''; title: string = '新对话'; streaming: boolean = false; stage: string = '';
  historyLoading: boolean = false; loading: boolean = false; historyError: string = ''; error: string = '';
  operationError: string = '';
  private epoch: number = 0; private historyEpoch: number = 0;
  private control?: StreamControl; private pending?: RunRequest; private assistantId: string = '';
  private session: Session;
  constructor(session: Session) { this.session = session; }

  reset(): void {
    this.control?.cancel(); this.control = undefined; this.epoch++; this.pending = undefined;
    this.messages = []; this.activeId = ''; this.title = '新对话'; this.streaming = false;
    this.error = ''; this.loading = false; this.operationError = ''; this.assistantId = ''; this.stage = '';
  }
  close(): void { this.reset(); this.historyEpoch++; this.sessions = []; this.historyLoading = false; this.historyError = ''; }
  async loadHistory(): Promise<void> {
    const epoch = ++this.historyEpoch; const revision = this.session.revision;
    this.historyLoading = true; this.historyError = '';
    try {
      const items = await this.session.authenticated((token: string) => this.session.api.call<Conversation[]>(http.RequestMethod.GET, '/api/v1/sessions', '', token));
      if (epoch !== this.historyEpoch || revision !== this.session.revision) return;
      this.sessions = items.sort((a: Conversation, b: Conversation) => Number(b.is_pinned) - Number(a.is_pinned) || b.updated_at.localeCompare(a.updated_at));
      this.title = items.find((item: Conversation) => item.session_id === this.activeId)?.title || this.title;
    } catch (error) { if (epoch === this.historyEpoch && revision === this.session.revision) this.historyError = errorText(error as Error); }
    finally { if (epoch === this.historyEpoch && revision === this.session.revision) this.historyLoading = false; }
  }
  async open(id: string): Promise<void> {
    this.reset(); const epoch = this.epoch; const revision = this.session.revision; this.loading = true;
    try {
      const detail = await this.session.authenticated((token: string) => this.session.api.call<ConversationDetail>(http.RequestMethod.GET, '/api/v1/sessions/' + encodeURIComponent(id), '', token));
      if (epoch !== this.epoch || revision !== this.session.revision) return;
      this.activeId = detail.session_id; this.title = detail.title;
      let messages: ChatMessage[] = [];
      detail.messages.forEach((item) => { messages = messages.concat(historyMessage(item)); });
      this.messages = messages;
    } catch (error) { if (epoch === this.epoch && revision === this.session.revision) { this.activeId = id; this.error = errorText(error as Error); } }
    finally { if (epoch === this.epoch && revision === this.session.revision) this.loading = false; }
  }
  async send(text: string, interaction?: Interaction): Promise<void> {
    if (!text.trim() || this.streaming || this.loading || this.pending) return;
    const run = new RunRequest();
    run.thread = this.activeId || util.generateRandomUUID(); run.run = util.generateRandomUUID();
    run.messageId = util.generateRandomUUID(); run.text = text.trim(); run.interaction = interaction;
    this.activeId = run.thread; this.assistantId = util.generateRandomUUID();
    this.messages = this.messages.concat([new ChatMessage(run.messageId, 'user', run.text), new ChatMessage(this.assistantId, 'assistant', '')]);
    this.pending = run; await this.execute(run);
  }
  async action(action: ResponseAction): Promise<void> {
    const text = action.params?.message;
    if (!text?.trim()) return;
    if (action.kind === 'clarify' && action.source_turn_id && action.params?.candidate_id) {
      const interaction: Interaction = { kind: 'clarification_choice', source_turn_id: action.source_turn_id, candidate_id: action.params.candidate_id };
      await this.send(text, interaction);
    } else if (action.kind === 'prompt') await this.send(text);
  }
  async retry(message: ChatMessage): Promise<void> {
    const index = this.messages.findIndex((item: ChatMessage) => item.id === message.id);
    const previous = this.messages.slice(0, index).reverse().find((item: ChatMessage) => item.role === 'user');
    if (previous) await this.send(previous.content);
  }
  async approve(decision: string): Promise<void> {
    const run = this.pending;
    const epoch = this.epoch; const revision = this.session.revision;
    if (!run || this.streaming) return;
    const approval = this.messages.find((item: ChatMessage) => item.id === this.assistantId)?.approval;
    if (!approval) return;
    const expiry = Date.parse(approval.expires_at);
    if (!Number.isFinite(expiry) || expiry <= Date.now()) {
      this.update((item: ChatMessage) => { item.approval = undefined; item.error = '确认已过期，请重新提问'; item.status = 'failed'; });
      this.pending = undefined; return;
    }
    this.streaming = true;
    try {
      await this.session.authenticated((token: string) => this.session.api.call<Object>(http.RequestMethod.POST, '/api/v1/agent-runs/approve-action',
        body({ "run_id": run.run, "request_id": util.generateRandomUUID(), "decision": decision, "note": null }), token));
      if (epoch !== this.epoch || revision !== this.session.revision) return;
      this.update((item: ChatMessage) => { item.approval = undefined; item.error = ''; });
      await this.execute(run);
    } catch (error) { if (epoch === this.epoch && revision === this.session.revision) { this.streaming = false; this.operationError = errorText(error as Error); } }
  }
  async stop(): Promise<void> {
    const run = this.pending; this.control?.cancel(); this.epoch++; this.streaming = false;
    const epoch = this.epoch; const revision = this.session.revision;
    this.pending = undefined; this.stage = '已停止';
    this.update((item: ChatMessage) => { item.status = 'cancelled'; item.approval = undefined; });
    if (!run) return;
    try {
      await this.session.authenticated((token: string) => this.session.api.call<Object>(http.RequestMethod.POST, '/api/v1/agent-runs/cancel',
        body({ "run_id": run.run, "request_id": util.generateRandomUUID(), "reason": 'user_cancelled' }), token));
    } catch (error) { if (epoch === this.epoch && revision === this.session.revision) this.operationError = errorText(error as Error); }
  }
  async pin(item: Conversation): Promise<void> { await this.edit(item, body({ "is_pinned": !item.is_pinned })); }
  async rename(item: Conversation, title: string): Promise<void> {
    if (!title.trim()) throw new ApiError(0, '请输入对话名称');
    await this.edit(item, body({ "title": title.trim() }));
  }
  private async edit(item: Conversation, payload: string): Promise<void> {
    const revision = this.session.revision;
    await this.session.authenticated((token: string) => this.session.api.call<Conversation>('PATCH', '/api/v1/sessions/' + encodeURIComponent(item.session_id), payload, token));
    if (revision === this.session.revision) await this.loadHistory();
  }
  async delete(item: Conversation): Promise<void> {
    const revision = this.session.revision;
    await this.session.authenticated((token: string) => this.session.api.call<Object>(http.RequestMethod.DELETE, '/api/v1/sessions/' + encodeURIComponent(item.session_id), '', token));
    if (revision !== this.session.revision) return;
    if (this.activeId === item.session_id) this.reset();
    await this.loadHistory();
  }
  private async execute(run: RunRequest): Promise<void> {
    const epoch = this.epoch; const revision = this.session.revision;
    const control = new StreamControl(); this.control = control; this.streaming = true; this.stage = '正在连接'; this.error = '';
    try {
      await this.session.authenticated((token: string) => this.session.api.stream(run, token, control, (event: WireEvent) => {
        if (epoch === this.epoch && revision === this.session.revision) this.receive(event);
      }));
      if (epoch === this.epoch && revision === this.session.revision) await this.loadHistory();
    } catch (error) { if (epoch === this.epoch && revision === this.session.revision) this.fail(errorText(error as Error)); }
    finally {
      if (epoch === this.epoch && revision === this.session.revision) {
        this.streaming = false;
        if (!this.messages.find((item: ChatMessage) => item.id === this.assistantId)?.approval) this.pending = undefined;
      }
    }
  }
  private receive(event: WireEvent): void {
    if (event.type === 'RUN_STARTED') this.stage = '正在处理';
    if (event.type === 'TOOL_CALL_START') this.stage = '正在查询数据';
    if (event.type === 'TOOL_CALL_RESULT' && event.content) {
      try { const data = JSON.parse(event.content) as Record<string, string>; if (data['label']) this.stage = data['label']; } catch (_) {}
    }
    this.update((item: ChatMessage) => {
      if (event.type === 'TEXT_MESSAGE_START' && item.content) item.content += '\n\n';
      if (event.type === 'TEXT_MESSAGE_CONTENT') item.content += event.delta || '';
      if (event.type === 'RUN_ERROR') { item.error = event.message?.trim() || '消息处理失败'; item.errorCode = event.code || ''; item.retryable = true; item.status = 'failed'; }
      if (event.type === 'RUN_FINISHED' && !item.status) item.status = 'ok';
      if (event.type === 'STATE_SNAPSHOT' && event.snapshot) {
        if (event.snapshot.approval_id) item.approval = event.snapshot;
        else {
          item.parts = supportedParts(event.snapshot.agent_response); item.actions = supportedActions(event.snapshot.agent_response);
          item.status = event.snapshot.agent_response?.result_status || '';
        }
      }
    });
  }
  private fail(text: string): void { this.update((item: ChatMessage) => { item.error = text; item.status = 'failed'; }); }
  private update(change: (item: ChatMessage) => void): void {
    this.messages = this.messages.map((old: ChatMessage) => {
      if (old.id !== this.assistantId) return old;
      const next = new ChatMessage(old.id, old.role, old.content);
      next.parts = old.parts; next.actions = old.actions; next.approval = old.approval; next.error = old.error; next.status = old.status;
      next.errorCode = old.errorCode; next.retryable = old.retryable;
      change(next); return next;
    });
  }
}
