export interface LoginResponse {
  token: string; refresh_token?: string; username: string; user_id: string; tenant_id?: string;
  role: string; has_password: boolean; workspace_type: string; active_workspace_id: string;
}
export interface PhoneStatus { is_registered: boolean; has_password: boolean }
export interface Verification { challenge_id: string; message: string; expires_in: number; resend_after: number }
export interface Confirmation { verification_token: string; expires_in: number }
export interface MessageResponse { message: string; has_password?: boolean }
export interface Profile { user_id: string; username: string; display_name: string; has_avatar: boolean }
export interface Workspace {
  workspace_id: string; workspace_type: string; name: string; tenant_id?: string; role: string; is_active: boolean;
}
export interface WorkspaceList { active_workspace_id: string; items: Workspace[] }
export interface Invitation { workspace: Workspace; message: string }
export interface Conversation { session_id: string; title: string; is_pinned: boolean; created_at: string; updated_at: string }
export interface ActionParams { candidate_id?: string; message?: string }
export interface ResponseAction { action_id: string; kind: string; label: string; source_turn_id?: string; params?: ActionParams }
export interface ResponseColumn { key: string; label: string; data_type?: string; unit?: string }
export type Cell = string | number | boolean | null | Cell[] | CellObject;
export interface CellObject extends Record<string, Cell> {}
export interface ResponseMetric { key: string; label?: string; value: string; unit?: string }
export interface Insight { statement_type: string; text: string; evidence_refs: string[] }
export interface ResponsePart {
  kind: string; title?: string; message?: string; metrics?: ResponseMetric[]; items?: Insight[];
  severity?: string; code?: string; reason_code?: string; missing_fields?: string[]; allow_free_text?: boolean;
  table_id?: string; row_count?: number; columns?: ResponseColumn[]; preview_rows?: Record<string, Cell>[];
}
export interface AgentResponse {
  version: number; domain?: string; task?: string; result_status?: string; result_id?: string;
  source_turn_id: string; parts?: ResponsePart[]; actions?: ResponseAction[];
}
export interface HistoryMetadata { agent_response?: AgentResponse; delivery_status?: string }
export interface HistoryMessage { id: string; role: string; content: string; created_at: string; metadata?: HistoryMetadata }
export interface ConversationDetail { session_id: string; title: string; messages: HistoryMessage[] }
export interface Approval { approval_id: string; tool_label: string; message: string; expires_at: string }
export interface Snapshot extends Approval { agent_response?: AgentResponse }
export interface WireEvent {
  type: string; eventId: string; sequence: number; runId: string; threadId: string;
  messageId?: string; role?: string; delta?: string; snapshot?: Snapshot; message?: string; code?: string; content?: string;
}
export interface Interaction { kind: string; source_turn_id: string; candidate_id: string }
export interface UserWireMessage { id: string; role: string; content: string }
export interface ForwardedProps { interaction?: Interaction; afterEventId?: string }
export interface RunBody {
  threadId: string; runId: string; parentRunId: null; state: Record<string, string>;
  messages: UserWireMessage[]; tools: string[]; context: string[]; forwardedProps: ForwardedProps;
}
export class ChatMessage {
  id: string = ''; role: string = 'assistant'; content: string = ''; parts: ResponsePart[] = [];
  actions: ResponseAction[] = []; status: string = ''; error: string = ''; errorCode: string = ''; retryable: boolean = true; approval?: Approval;
  constructor(id: string, role: string, content: string) { this.id = id; this.role = role; this.content = content; }
}
export interface Metric { current?: number; previous?: number; difference?: number; change_rate?: number; status?: string }
export interface Dimension {
  dim_key?: string; dim_label?: string; store_key?: string; store_label?: string; metrics: Record<string, Metric>;
}
export interface DateRange { date_from: string; date_to: string }
export interface Overview {
  period: DateRange; previous_period?: DateRange; metrics: Record<string, Metric>;
  channels: Dimension[]; stores: Dimension[]; generated_at?: string;
}
