import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { LoginResponse, Profile, Workspace, WorkspaceList, Invitation, MessageResponse } from '../core/Models';
import { Api, ApiError, AUTH, body, errorText } from './Api';
import { TokenStore } from './TokenStore';
import { settings } from './Settings';

@Observed
export class Session {
  state: string = 'restoring'; error: string = ''; user?: LoginResponse;
  displayName: string = ''; avatar?: image.PixelMap; workspaces: Workspace[] = []; workspaceError: string = '';
  workspaceBusy: boolean = false; revision: number = 0;
  api: Api = new Api();
  private vault: TokenStore = new TokenStore();
  private accessToken: string = ''; private epoch: number = 0;
  private refreshTask?: Promise<string>;
  private switching: boolean = false;

  async restore(): Promise<void> {
    if (this.state === 'clearing') return;
    if (this.state === 'cleanupError') { await this.clear(); return; }
    const epoch = ++this.epoch; this.refreshTask = undefined;
    this.state = 'restoring'; this.error = '';
    try {
      if (settings.sessionRestoreBlocked()) { await this.clear(); return; }
      const refresh = this.vault.read();
      if (!refresh) { this.state = 'signedOut'; return; }
      const result = await this.api.call<LoginResponse>(http.RequestMethod.POST, AUTH + 'refresh', body({ "client_type": 'mobile', "refresh_token": refresh }));
      if (epoch !== this.epoch) return;
      this.apply(result, refresh); await this.loadAccount(true);
    } catch (error) {
      if (epoch !== this.epoch) return;
      if (error instanceof ApiError && error.status === 401) await this.clear();
      else { this.state = 'restoreError'; this.error = errorText(error as Error); }
    }
  }
  async signIn(path: string, payload: string): Promise<void> {
    if (this.state === 'clearing' || this.state === 'cleanupError') throw new ApiError(0, '请先重试清理登录凭据');
    const epoch = ++this.epoch; this.refreshTask = undefined;
    await settings.setSessionRestoreBlocked(false);
    if (epoch !== this.epoch) return;
    const result = await this.api.call<LoginResponse>(http.RequestMethod.POST, AUTH + path, payload);
    if (epoch !== this.epoch) return;
    this.apply(result, ''); await this.loadAccount(true);
  }
  async authenticated<T>(operation: (token: string) => Promise<T>): Promise<T> {
    const epoch = this.epoch;
    let first = this.accessToken;
    if (!first || this.state !== 'signedIn') throw new ApiError(401, '请重新登录');
    if (this.shouldRefresh(first)) {
      first = await this.refresh();
      if (epoch !== this.epoch) throw new ApiError(409, '登录或工作空间已变更，请重试');
    }
    try {
      const result = await operation(first);
      if (epoch !== this.epoch) throw new ApiError(409, '登录或工作空间已变更，请重试');
      return result;
    } catch (error) {
      if (!(error instanceof ApiError) || error.status !== 401 || epoch !== this.epoch) throw error as Error;
      const token = this.accessToken !== first ? this.accessToken : await this.refresh();
      if (epoch !== this.epoch) throw new ApiError(401, '工作空间已变更，请重试');
      try {
        const result = await operation(token);
        if (epoch !== this.epoch) throw new ApiError(409, '登录或工作空间已变更，请重试');
        return result;
      } catch (second) {
        if (second instanceof ApiError && second.status === 401 && epoch === this.epoch) await this.clear();
        throw second as Error;
      }
    }
  }
  private shouldRefresh(token: string): boolean {
    // Same six-hour threshold as iOS; this hint never replaces server authentication.
    try {
      const parts = token.split('.'); if (parts.length < 2) return false;
      let payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      payload += '='.repeat((4 - payload.length % 4) % 4);
      const bytes = new util.Base64Helper().decodeSync(payload);
      const values = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as Record<string, number>;
      return typeof values['exp'] === 'number' && Number.isFinite(values['exp']) && values['exp'] - Date.now() / 1000 <= 6 * 60 * 60;
    } catch (_) { return false; }
  }
  private async refresh(): Promise<string> {
    if (this.refreshTask) return this.refreshTask;
    const task = this.refreshNow(); this.refreshTask = task;
    try { return await task; } finally { if (this.refreshTask === task) this.refreshTask = undefined; }
  }
  private async refreshNow(): Promise<string> {
    const epoch = this.epoch;
    try {
      const refresh = this.vault.read();
      if (!refresh) throw new ApiError(401, '登录已失效，请重新登录');
      const result = await this.api.call<LoginResponse>(http.RequestMethod.POST, AUTH + 'refresh', body({ "client_type": 'mobile', "refresh_token": refresh }));
      if (epoch !== this.epoch) throw new ApiError(401, '登录状态已变更');
      this.apply(result, refresh, false); return result.token;
    } catch (error) {
      if (error instanceof ApiError && error.status === 401 && epoch === this.epoch) await this.clear();
      throw error as Error;
    }
  }
  async loadWorkspaces(): Promise<void> {
    const epoch = this.epoch; this.workspaceBusy = true; this.workspaceError = '';
    try {
      const response = await this.authenticated((token: string) => this.api.call<WorkspaceList>(http.RequestMethod.GET, AUTH + 'workspaces', '', token));
      if (epoch === this.epoch) this.workspaces = response.items;
    } catch (error) { if (epoch === this.epoch) this.workspaceError = errorText(error as Error); }
    finally { if (epoch === this.epoch) this.workspaceBusy = false; }
  }
  async loadAccount(restoreWorkspace: boolean = false): Promise<void> {
    const epoch = this.epoch;
    await this.loadWorkspaces();
    if (epoch !== this.epoch || this.state !== 'signedIn') return;
    if (restoreWorkspace && !this.workspaceError && this.user) {
      try {
        const remembered = settings.lastWorkspace(this.user.user_id);
        if (remembered && remembered !== this.user.active_workspace_id && this.workspaces.some((item: Workspace) => item.workspace_id === remembered)) {
          await this.switchWorkspace(remembered); return;
        }
        await settings.rememberWorkspace(this.user.user_id, this.user.active_workspace_id);
      } catch (_) { /* Remembering a workspace is optional; authorization still comes from the server. */ }
    }
    if (epoch !== this.epoch || this.state !== 'signedIn') return;
    try { await this.loadProfile(); } catch (_) { /* Profile failure does not discard valid authentication. */ }
  }
  async loadProfile(): Promise<void> {
    const epoch = this.epoch;
    const profile = await this.authenticated((token: string) => this.api.call<Profile>(http.RequestMethod.GET, AUTH + 'profile', '', token));
    if (epoch !== this.epoch) return;
    this.displayName = profile.display_name || profile.username;
    if (profile.has_avatar) {
      const data = await this.authenticated((token: string) => this.api.avatar(token));
      const source = image.createImageSource(data);
      try {
        const pixel = await source.createPixelMap();
        if (epoch === this.epoch) { this.avatar?.release(); this.avatar = pixel; } else pixel.release();
      } finally { source.release(); }
    } else { this.avatar?.release(); this.avatar = undefined; }
  }
  async setName(name: string): Promise<void> {
    const normalized = name.trim();
    if (!normalized || Array.from(normalized).length > 30) throw new ApiError(0, '昵称需为 1 至 30 个字符');
    const epoch = this.epoch;
    const profile = await this.authenticated((token: string) => this.api.call<Profile>('PATCH', AUTH + 'profile', body({ "display_name": normalized }), token));
    if (epoch === this.epoch) this.displayName = profile.display_name;
  }
  async setAvatar(data: ArrayBuffer): Promise<void> {
    const epoch = this.epoch;
    await this.authenticated((token: string) => this.api.uploadAvatar(data, token));
    if (epoch !== this.epoch) return;
    await this.loadProfile();
  }
  async join(invite: string): Promise<string> {
    if (!invite.trim()) throw new ApiError(0, '请输入邀请码');
    const epoch = this.epoch;
    const result = await this.authenticated((token: string) => this.api.call<Invitation>(http.RequestMethod.POST, AUTH + 'accept-invite', body({ "invite_token": invite.trim() }), token));
    if (epoch === this.epoch) await this.loadWorkspaces(); return result.message;
  }
  async changePassword(old: string, next: string): Promise<void> {
    const epoch = this.epoch;
    if (next.length < 7 || next.length > 16) throw new ApiError(0, '密码需为 7 至 16 位');
    const hasPassword = this.user?.has_password === true;
    if (hasPassword && !old) throw new ApiError(0, '请输入当前密码');
    const payload = hasPassword ? body({ "old_password": old, "new_password": next }) : body({ "new_password": next });
    await this.authenticated((token: string) => this.api.call<MessageResponse>(http.RequestMethod.POST, AUTH + (hasPassword ? 'change-password' : 'password/initial'), payload, token));
    if (epoch === this.epoch && this.user) this.user.has_password = true;
  }
  async switchWorkspace(id: string): Promise<void> {
    if (this.switching || id === this.user?.active_workspace_id) return;
    const epoch = this.epoch; let activeEpoch = epoch; this.switching = true;
    try {
      const result = await this.authenticated((token: string) => this.api.call<LoginResponse>(http.RequestMethod.POST, AUTH + 'workspaces/switch',
        body({ "workspace_id": id, "client_type": 'mobile', "refresh_token": this.vault.read() }), token));
      if (epoch !== this.epoch) return;
      // Persist first: a failed secure write must not invalidate the still-active workspace.
      this.apply(result, this.vault.read()); activeEpoch = ++this.epoch; this.refreshTask = undefined; this.switching = true;
      try { await settings.rememberWorkspace(result.user_id, result.active_workspace_id); } catch (_) {}
      if (activeEpoch === this.epoch) await this.loadAccount();
    } finally { if (activeEpoch === this.epoch) this.switching = false; }
  }
  async signOut(): Promise<void> {
    if (this.state === 'clearing') return;
    let refresh = '';
    try { refresh = this.vault.read(); } catch (_) { /* Unreadable credentials must not prevent local cleanup. */ }
    await this.clear();
    if (refresh) {
      try { await this.api.call<MessageResponse>(http.RequestMethod.POST, AUTH + 'logout', body({ "client_type": 'mobile', "refresh_token": refresh })); } catch (_) {}
    }
  }
  private apply(result: LoginResponse, fallback: string, reset: boolean = true): void {
    const refresh = result.refresh_token || fallback;
    if (!result.token || !refresh) throw new ApiError(0, '服务器未返回有效登录凭据');
    this.vault.write(refresh); this.accessToken = result.token; this.user = result; this.state = 'signedIn';
    if (reset) { this.resetAccount(); this.displayName = result.username; this.revision++; }
  }
  private resetAccount(): void {
    this.avatar?.release(); this.avatar = undefined; this.displayName = ''; this.workspaces = [];
    this.workspaceBusy = false; this.workspaceError = ''; this.switching = false;
  }
  private async clear(): Promise<void> {
    // Invalidate all in-flight work before touching storage or the network.
    this.epoch++; this.refreshTask = undefined; this.accessToken = ''; this.user = undefined;
    this.resetAccount(); this.revision++; this.state = 'clearing'; this.error = '';
    let blocked = false;
    try { await settings.setSessionRestoreBlocked(true); blocked = true; } catch (_) {}
    try { this.vault.clear(); this.state = 'signedOut'; }
    catch (_) {
      this.state = 'cleanupError';
      this.error = blocked ? '登录凭据清理失败，已阻止自动登录，请重试' : '退出状态未能保存，请勿关闭应用，重试清理登录凭据';
    }
  }
}
