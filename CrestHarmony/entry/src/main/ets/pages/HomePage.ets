import { localizedFormat } from '../core/Localization';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { Session } from '../services/Session';
import { settings } from '../services/Settings';
import { errorText } from '../services/Api';
import { ChatStore } from '../state/ChatStore';
import { ChatMessage, Conversation, ResponseAction, Workspace } from '../core/Models';
import { validPassword } from '../core/Protocol';
import { Palette, CrestIcon, IconButton, StateMessage } from '../components/Theme';
import { RichMessage } from '../components/RichMessage';
import { ProfileEditor } from '../components/ProfileEditor';
import { AnalyticsPage } from './AnalyticsPage';

@Component
export struct HomePage {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @ObjectLink @Watch('sessionChanged') session: Session;
  registerBack: (handler: () => boolean) => void = () => {};
  @StorageLink('dark') dark: boolean = true;
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('appearance') appearance: string = 'dark';
  @StorageLink('language') language: string = 'system';
  @State @Watch('chatChanged') chat: ChatStore = new ChatStore(new Session());
  @State sidebar: boolean = false; @State destination: string = 'chat'; @State sheet: boolean = false;
  @State sidebarDrag: number = 0; @State drawerWidth: number = 360;
  private sidebarGestureAccepted: boolean = false;
  @State panel: string = 'settings'; @State draft: string = ''; @State search: string = '';
  @State form: string = ''; @State oldPassword: string = ''; @State confirmation: string = '';
  @State sheetError: string = ''; @State busy: boolean = false;
  @State completion: string = ''; @State completionTitle: string = ''; @State completionMessage: string = '';
  @State followBottom: boolean = true;
  @State dialog: boolean = false;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private selected?: Conversation; private lastRevision: number = -1;
  private scroller: Scroller = new Scroller(); private scrollTimer: number = -1;
  aboutToAppear(): void {
    this.chat = new ChatStore(this.session); this.lastRevision = this.session.revision;
    this.chat.loadHistory(); this.registerBack(() => this.back());
  }
  aboutToDisappear(): void { this.chat.close(); clearTimeout(this.scrollTimer); this.registerBack(() => false); }
  private sessionChanged(): void {
    if (this.lastRevision === this.session.revision) return;
    this.lastRevision = this.session.revision; this.chat.close(); this.draft = ''; this.destination = 'chat';
    this.sheet = false; this.dialog = false; this.busy = false; this.search = ''; this.selected = undefined;
    this.sidebar = false; this.sidebarDrag = 0; this.sidebarGestureAccepted = false;
    this.form = ''; this.oldPassword = ''; this.confirmation = ''; this.sheetError = '';
    this.completion = ''; this.completionTitle = ''; this.completionMessage = '';
    if (this.session.state === 'signedIn') this.chat.loadHistory();
  }
  private chatChanged(): void {
    if (!this.followBottom || this.destination !== 'chat') return;
    clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 40);
  }
  private back(): boolean {
    if (this.busy || this.completion) return true;
    if (this.dialog) { this.dialog = false; return true; }
    if (this.sheet) { if (this.panel !== 'settings') this.openPanel('settings'); else this.sheet = false; return true; }
    if (this.sidebar) { this.sidebar = false; return true; }
    if (this.destination !== 'chat') { this.destination = 'chat'; return true; }
    return false;
  }
  private canSend(): boolean { return !this.chat.streaming && !this.chat.loading && !this.chat.messages.some((item: ChatMessage) => !!item.approval); }
  private send(text: string): void {
    if (!this.canSend() || !text.trim()) return;
    this.draft = ''; this.followBottom = true; this.chat.send(text);
  }
  private openPanel(panel: string, item?: Conversation): void {
    this.panel = panel; this.selected = item; this.form = panel === 'rename' ? item?.title || '' : '';
    this.oldPassword = ''; this.confirmation = ''; this.sheetError = ''; this.completion = '';
    this.dialog = panel === 'rename' || panel === 'delete'; this.sheet = !this.dialog;
    if (panel === 'settings') this.session.loadAccount();
  }
  private async perform(action: () => Promise<void>, close: boolean = false): Promise<void> {
    if (this.busy) return;
    const revision = this.session.revision;
    this.busy = true; this.sheetError = '';
    try { await action(); if (close && revision === this.session.revision) { this.sheet = false; this.dialog = false; } }
    catch (error) { if (revision === this.session.revision) this.sheetError = errorText(error as Error); }
    finally { if (revision === this.session.revision) this.busy = false; }
  }
  private async submitAccount(): Promise<void> {
    if (this.busy) return;
    const revision = this.session.revision;
    const joining = this.panel === 'join', changing = this.session.user?.has_password === true;
    this.busy = true; this.sheetError = '';
    try {
      if (joining) {
        const message = await this.session.join(this.form);
        if (revision !== this.session.revision) return;
        this.completionMessage = message;
        this.completionTitle = '已加入团队'; this.completion = 'joined';
      } else {
        await this.session.changePassword(this.oldPassword, this.form);
        if (revision !== this.session.revision) return;
        this.completionTitle = changing ? '密码修改成功' : '密码设置成功';
        this.completionMessage = changing ? '为了保护账号安全，请使用新密码重新登录' : '密码已设置完成';
        this.completion = changing ? 'reauthenticate' : 'initial';
      }
      this.form = ''; this.oldPassword = ''; this.confirmation = '';
    } catch (error) {
      if (revision !== this.session.revision) return;
      this.completionTitle = joining ? '加入团队失败' : changing ? '密码修改失败' : '密码设置失败';
      this.completionMessage = errorText(error as Error); this.completion = 'error';
    } finally { if (revision === this.session.revision) this.busy = false; }
  }
  private async finishAccount(): Promise<void> {
    const outcome = this.completion; this.completion = '';
    if (outcome === 'reauthenticate') await this.perform(async () => { this.chat.close(); await this.session.signOut(); }, true);
    else if (outcome !== 'error') this.openPanel('settings');
  }
  private choose(item: Conversation): void {
    this.destination = 'chat'; this.sidebar = false; this.followBottom = true; this.chat.open(item.session_id);
  }
  private fresh(): void { this.chat.reset(); this.draft = ''; this.sidebar = false; this.destination = 'chat'; this.followBottom = true; }
  private suggestions(): string[] {
    return this.session.user?.tenant_id ? [this.t('分析本月经营情况'), this.t('找出最近的异常费用'), this.t('生成一份经营摘要')] :
      [this.t('帮我设计一份菜单结构'), this.t('如何控制餐厅食材成本'), this.t('制定新店开业推广计划')];
  }
  private suggestionIcon(index: number): string {
    return (this.session.user?.tenant_id ? ['chart', 'alert-search', 'document'] : ['menu-card', 'pie-chart', 'megaphone'])[index];
  }
  private beginSidebarDrag(event: GestureEvent): void {
    const finger = event.fingerList[0];
    const startX = finger ? finger.globalX - event.offsetX : Number.POSITIVE_INFINITY;
    this.sidebarGestureAccepted = !this.sheet && !this.dialog && (this.sidebar || (startX >= 0 && startX <= 32));
    this.moveSidebarDrag(event);
  }
  private moveSidebarDrag(event: GestureEvent): void {
    if (!this.sidebarGestureAccepted || Math.abs(event.offsetX) <= Math.abs(event.offsetY)) return;
    const next = this.sidebar ? Math.max(-this.drawerWidth, Math.min(0, event.offsetX)) : Math.min(this.drawerWidth, Math.max(0, event.offsetX));
    if (next > 0 && this.sidebarDrag === 0) this.getUIContext().getFocusController().clearFocus();
    this.sidebarDrag = next;
  }
  private settleSidebar(open: boolean, duration: number = 240): void {
    const update = (): void => { this.sidebar = open; this.sidebarDrag = 0; };
    if (this.reduceMotion) update(); else animateTo({ duration: duration, curve: Curve.EaseOut }, update);
  }
  private finishSidebarDrag(event?: GestureEvent): void {
    const wasOpen = this.sidebar;
    let open = wasOpen;
    if (event && this.sidebarGestureAccepted && this.sidebarDrag !== 0) {
      const direction = wasOpen ? -1 : 1;
      const distance = direction * this.sidebarDrag;
      // ArkUI has no predictedEndTranslation. Project 200 ms using native vp/s velocity.
      const projected = distance + Math.max(0, direction * event.velocityX) * .2;
      const crossed = distance >= this.drawerWidth * .34 || projected >= this.drawerWidth * .5;
      open = wasOpen ? !crossed : crossed;
    }
    this.sidebarGestureAccepted = false;
    this.settleSidebar(open);
    if (open && !wasOpen) this.chat.loadHistory();
  }
  @Builder private heading() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        IconButton({ kind: 'menu', label: this.t('打开侧边栏'), iconSize: 17, action: () => this.settleSidebar(true) })
        Blank().layoutWeight(1)
        if (this.destination === 'chat') { IconButton({ kind: 'edit', label: this.t('新对话'), iconSize: 17, action: () => this.fresh() }) }
        IconButton({ kind: 'person', label: this.t('设置'), iconSize: 20, action: () => this.openPanel('settings') })
      }.width('100%')
      Text(this.destination === 'chat' ? this.chat.title : this.t(this.destination === 'analytics' ? '经营分析' : '搜索对话'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center).width('50%')
    }.height(56).padding({ left: 10, right: 10 }).width('100%')
  }
  @Builder private composer() {
    Column({ space: 5 }) {
      if (this.chat.operationError) { Text(this.chat.operationError).fontSize(12).fontColor(Palette.error(this.dark)).padding({ left: 20, right: 20 }) }
      Row({ space: 8 }) {
        TextArea({ placeholder: this.t('给 Crest 发消息'), text: this.draft }).id('chatComposer').onChange((value: string) => this.draft = value)
          .fontSize(16).fontColor(Palette.text(this.dark)).placeholderColor(this.dark ? '#8E8E93' : '#C7C7CC')
          .backgroundColor(Color.Transparent).padding({ left: 8, right: 8, top: 0, bottom: 0 })
          .constraintSize({ minHeight: 38, maxHeight: 132 }).layoutWeight(1).maxLength(16000)
        IconButton({ kind: this.chat.streaming ? 'stop' : 'send', label: this.chat.streaming ? this.t('停止回复') : this.t('发送'), glass: false, filled: true,
          isEnabled: this.chat.streaming || (this.canSend() && !!this.draft.trim()), action: () => { if (this.chat.streaming) this.chat.stop(); else this.send(this.draft); } })
      }.padding(7).backgroundColor(Palette.input(this.dark))
        .border({ width: 1, color: Palette.border(this.dark) }).borderRadius(28).margin({ left: 25, right: 25, bottom: 8 })
    }.width('100%')
  }
  @Builder private chatPage() {
    Column() {
      this.heading()
      Divider().color(Palette.border(this.dark))
      if (!this.session.user?.tenant_id && !this.session.user?.has_password) {
        Button(this.t('完善密码')).width('100%').height(44).borderRadius(0).fontColor(Palette.accent(this.dark))
          .backgroundColor(Palette.surface(this.dark)).onClick(() => this.openPanel('password'))
      }
      if (this.chat.loading) { StateMessage({ title: this.t('正在加载对话'), busy: true }).layoutWeight(1) }
      else if (this.chat.error) { StateMessage({ title: this.t('对话加载失败'), detail: this.chat.error, action: this.t('重试'), onAction: () => this.chat.open(this.chat.activeId) }).layoutWeight(1) }
      else if (!this.chat.messages.length) {
        Column({ space: 22 }) {
          Text('C').fontFamily('CrestRoundedBold').fontSize(24).fontColor(Palette.text(this.dark)).width(58).height(58)
            .textAlign(TextAlign.Center).borderRadius(29).backgroundColor(Palette.surface(this.dark)).border({ width: 1, color: Palette.border(this.dark) })
            .shadow({ radius: 14, color: this.dark ? '#26000000' : '#12000000', offsetY: 6 })
          Text(this.t('今天想一起处理什么？')).fontSize(25).fontWeight(600).fontColor(Palette.text(this.dark)).textAlign(TextAlign.Center)
          Text(this.t('从一个餐饮经营问题开始')).fontSize(14).fontColor(Palette.secondary(this.dark))
        }.padding(28).layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          List({ space: 22, scroller: this.scroller }) {
            ForEach(this.chat.messages, (message: ChatMessage, index: number) => {
              ListItem() {
                RichMessage({ message: message, streaming: this.chat.streaming && index === this.chat.messages.length - 1,
                  stage: this.chat.stage, canAct: this.canSend(), onRetry: () => { this.followBottom = true; this.chat.retry(message); },
                  onAction: (action: ResponseAction) => { this.followBottom = true; this.chat.action(action); }, onApproval: (decision: string) => this.chat.approve(decision) })
              }
            }, (message: ChatMessage) => message.id)
          }.width('100%').height('100%').padding({ left: 20, right: 20, top: 20, bottom: 22 })
            .onScroll((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll && offset < 0) this.followBottom = false; })
            .onReachEnd(() => this.followBottom = true)
          if (!this.followBottom) {
            Button(this.t('回到最新')).fontSize(12).height(36).backgroundColor(Palette.glass(this.dark)).fontColor(Palette.text(this.dark)).margin(12)
              .onClick(() => { this.followBottom = true; this.scroller.scrollEdge(Edge.Bottom); })
          }
        }.layoutWeight(1).width('100%')
      }
      if (!this.chat.loading && !this.chat.messages.length) {
        Column({ space: 8 }) {
          ForEach(this.suggestions(), (suggestion: string, index: number) => {
            Button() {
              Row({ space: 10 }) {
                CrestIcon({ kind: this.suggestionIcon(index), iconSize: 20, color: Palette.text(this.dark) })
                Text(suggestion).fontSize(14).fontColor(Palette.text(this.dark))
              }
            }.padding({ left: 14, right: 14 }).backgroundColor(Palette.surface(this.dark))
              .height(42).borderRadius(21).border({ width: 1, color: Palette.border(this.dark) })
              .onClick(() => { this.draft = suggestion; this.getUIContext().getFocusController().requestFocus('chatComposer'); })
          })
        }.alignItems(HorizontalAlign.Start).padding({ left: 25, right: 25, bottom: 8 }).width('100%')
      }
      this.composer()
    }.width('100%').height('100%')
  }
  @Builder private historyAction(icon: string, label: string, destructive: boolean = false) {
    Row({ space: 12 }) {
      CrestIcon({ kind: icon, iconSize: 18, color: destructive ? Palette.error(this.dark) : Palette.text(this.dark) })
      Text(label).fontSize(16).fontColor(destructive ? Palette.error(this.dark) : Palette.text(this.dark)).layoutWeight(1)
    }.height(44).width('100%')
  }
  @Builder private contextMenu(item: Conversation) {
    Menu() {
      MenuItem(this.historyAction('pin', item.is_pinned ? this.t('取消固定') : this.t('固定'))).onClick(() => { this.chat.pin(item).catch((error: Error) => this.getUIContext().getPromptAction().showToast({ message: errorText(error) })); })
      MenuItem(this.historyAction('edit', this.t('重命名'))).onClick(() => this.openPanel('rename', item))
      MenuItem(this.historyAction('trash', this.t('删除'), true)).onClick(() => this.openPanel('delete', item))
    }.width(240)
  }
  @Builder private historyPreview(item: Conversation) {
    Row({ space: 8 }) {
      Text(item.title || this.t('新对话')).fontSize(16).fontColor(Palette.text(this.dark))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (item.is_pinned) { CrestIcon({ kind: 'pin', iconSize: 13, color: Palette.secondary(this.dark) }) }
    }.padding({ left: 18, right: 18 }).height(48).width(this.drawerWidth - 20)
      .borderRadius(24).backgroundColor(Palette.surface(this.dark)).backgroundBlurStyle(BlurStyle.Thin)
  }
  @Builder private history(items: Conversation[]) {
    if (this.chat.historyLoading && !items.length) { StateMessage({ title: this.t('正在加载历史记录'), busy: true }) }
    else if (this.chat.historyError) { StateMessage({ title: this.t('历史记录加载失败'), detail: this.chat.historyError, action: this.t('重试'), onAction: () => this.chat.loadHistory() }) }
    else if (!items.length) { StateMessage({ title: this.search ? this.t('没有找到相关对话') : this.t('暂无历史记录'), detail: this.search ? this.t('试试其他对话标题') : this.t('开始一段新的对话吧') }) }
    else {
      List({ space: 2 }) {
        ForEach(items, (item: Conversation) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item.title || this.t('新对话')).fontSize(16).fontWeight(item.session_id === this.chat.activeId ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(Palette.text(this.dark)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (item.is_pinned) { CrestIcon({ kind: 'pin', iconSize: 13, color: Palette.secondary(this.dark) }) }
            }.padding({ left: 18, right: 18 }).height(44).width('100%').borderRadius(22)
              .backgroundColor(item.session_id === this.chat.activeId ? (this.dark ? '#08ECECEC' : '#080D0D0D') : Color.Transparent)
              .onClick(() => this.choose(item)).bindContextMenu(this.contextMenu(item), ResponseType.LongPress, { preview: this.historyPreview(item) })
          }
        }, (item: Conversation) => item.session_id)
      }.width('100%').layoutWeight(1)
    }
  }
  @Builder private sideRow(icon: string, title: string, action: () => void, height: number = 52, secondary: boolean = false) {
    Row({ space: 12 }) {
      CrestIcon({ kind: icon, color: secondary ? Palette.secondary(this.dark) : Palette.text(this.dark) })
      Text(title).fontSize(16).fontWeight(secondary ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(secondary ? Palette.secondary(this.dark) : Palette.text(this.dark)).layoutWeight(1)
    }.height(height).padding({ left: 14, right: 14 }).width('100%').borderRadius(14).onClick(action).accessibilityGroup(true)
  }
  @Builder private sidebarContent() {
    Column() {
      Row() { Text('Crest').fontFamily('CrestRounded').fontSize(26).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).layoutWeight(1); IconButton({ kind: 'close', label: this.t('关闭侧边栏'), iconSize: 17, action: () => this.sidebar = false }).backgroundColor(this.dark ? '#292929' : '#FFFFFF').borderRadius(22).shadow({ radius: 12, color: this.dark ? '#20000000' : '#10000000', offsetY: 4 }) }.padding({ left: 6, right: 6, top: 10, bottom: 24 })
      this.sideRow('edit', this.t('发起新对话'), () => this.fresh(), 36)
      this.sideRow('search', this.t('搜索对话内容'), () => { this.destination = 'search'; this.sidebar = false; this.search = ''; this.chat.loadHistory(); }, 48, true)
      if (this.session.user?.tenant_id) { this.sideRow('chart', this.t('经营分析'), () => { this.destination = 'analytics'; this.sidebar = false; }, 48, true) }
      Divider().color(Palette.border(this.dark))
      Row() {
        Text(this.t('最近')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Palette.secondary(this.dark)).layoutWeight(1)
        IconButton({ kind: 'retry', label: this.t('刷新最近对话'), glass: false, iconSize: 14, isEnabled: !this.chat.historyLoading, action: () => this.chat.loadHistory() })
      }.height(36).padding({ left: 14, top: 14 }).width('100%')
      this.history(this.chat.sessions)
      Row({ space: 12 }) {
        if (this.session.avatar) { Image(this.session.avatar).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover) }
        else { CrestIcon({ kind: 'person', iconSize: 34, color: Palette.secondary(this.dark) }) }
        Text(this.session.displayName || this.t('账户设置')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).layoutWeight(1)
        CrestIcon({ kind: 'gear', iconSize: 20, color: Palette.text(this.dark) }).width(44)
      }.padding({ left: 4, right: 4, top: 30, bottom: 8 }).width('100%').backgroundColor(Palette.sidebar(this.dark))
        .onClick(() => { this.sidebar = false; this.openPanel('settings'); })
    }.width('100%').height('100%').padding(12)
      .backgroundColor(Palette.sidebar(this.dark))
      .translate({ x: this.sidebar ? this.sidebarDrag : -this.drawerWidth + this.sidebarDrag })
      .transition(TransitionEffect.move(TransitionEdge.START))
  }
  @Builder private settingsItem(icon: string, title: string, value: string, action: () => void) {
    Row({ space: 14 }) {
      CrestIcon({ kind: icon, iconSize: 19, color: Palette.text(this.dark) }).width(28)
      Text(title).fontSize(16).fontColor(Palette.text(this.dark)).maxLines(1)
      Blank().layoutWeight(1)
      if (value) { Text(value).fontSize(16).fontColor(Palette.secondary(this.dark)).maxLines(1) }
      CrestIcon({ kind: 'next', iconSize: 13, color: Palette.secondary(this.dark) })
    }.height(52).padding({ left: 16, right: 16 }).width('100%').onClick(action)
  }
  @Builder private settingsHeading(title: string) {
    Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.secondary(this.dark))
      .alignSelf(ItemAlign.Start).padding({ left: 4, bottom: 10 })
  }
  @Builder private settingsContent() {
    Column() {
      Column({ space: 12 }) {
        if (this.session.avatar) { Image(this.session.avatar).width(74).height(74).borderRadius(37).objectFit(ImageFit.Cover) }
        else { CrestIcon({ kind: 'person', iconSize: 74, color: Palette.text(this.dark) }) }
        Text(this.session.displayName || this.t('个人资料')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.text(this.dark))
      }.width('100%').padding({ top: 16, bottom: 22 }).onClick(() => this.openPanel('profile'))
      this.settingsHeading(this.t('账户'))
      Column() {
        this.settingsItem('person', this.t('个人资料'), this.session.displayName, () => this.openPanel('profile'))
        Divider().color(Palette.border(this.dark)).margin({ left: 58 })
        this.settingsItem('lock', this.session.user?.has_password ? this.t('修改密码') : this.t('设置密码'), '', () => this.openPanel('password'))
      }.width('100%').borderRadius(24).backgroundColor(Palette.surface(this.dark)).margin({ bottom: 20 })
      this.settingsHeading(this.t('工作空间'))
      Column() {
        ForEach(this.session.workspaces, (workspace: Workspace, index: number) => {
          if (index > 0) { Divider().color(Palette.border(this.dark)).margin({ left: 58 }) }
          Row({ space: 14 }) {
            CrestIcon({ kind: workspace.workspace_type === 'personal' ? 'person' : 'team', iconSize: 19, color: Palette.text(this.dark) }).width(28)
            Column({ space: 3 }) {
              Text(workspace.name).fontSize(16).fontColor(Palette.text(this.dark)).maxLines(1)
              Text(workspace.workspace_type === 'personal' ? this.t('个人账号') : workspace.role).fontSize(12).fontColor(Palette.secondary(this.dark)).maxLines(1)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (workspace.workspace_id === this.session.user?.active_workspace_id) {
              CrestIcon({ kind: 'check-circle', iconSize: 19, color: Palette.accent(this.dark) })
            }
          }.height(56).padding({ left: 16, right: 16 }).width('100%')
            .enabled(!this.busy && workspace.workspace_id !== this.session.user?.active_workspace_id)
            .onClick(() => this.perform(async () => { await this.session.switchWorkspace(workspace.workspace_id); }, true))
        }, (workspace: Workspace) => workspace.workspace_id)
        if (this.session.workspaces.length) { Divider().color(Palette.border(this.dark)).margin({ left: 58 }) }
        this.settingsItem('team', this.t('加入新团队'), '', () => this.openPanel('join'))
      }.width('100%').borderRadius(24).backgroundColor(Palette.surface(this.dark)).margin({ bottom: 26 })
      if (this.session.workspaceBusy) { LoadingProgress().width(26).height(26) }
      if (this.session.workspaceError) { StateMessage({ title: this.t('工作空间加载失败'), detail: this.session.workspaceError, action: this.t('重试'), onAction: () => this.session.loadWorkspaces() }) }
      this.settingsHeading(this.t('外观与语言'))
      Column() {
        Row({ space: 14 }) {
          CrestIcon({ kind: 'sun', iconSize: 19, color: Palette.text(this.dark) }).width(28)
          Text(this.t('外观')).fontSize(16).fontColor(Palette.text(this.dark)).layoutWeight(1)
          Select([{ value: this.t('跟随系统') }, { value: this.t('浅色') }, { value: this.t('深色') }])
            .selected(['system', 'light', 'dark'].indexOf(this.appearance))
            .value(this.appearance === 'system' ? this.t('跟随系统') : this.appearance === 'light' ? this.t('浅色') : this.t('深色'))
            .onSelect((index: number) => this.perform(async () => { await settings.setMode(['system', 'light', 'dark'][index]); }))
        }.height(52).padding({ left: 16, right: 16 }).width('100%')
        Divider().color(Palette.border(this.dark)).margin({ left: 58 })
        Row({ space: 14 }) {
          CrestIcon({ kind: 'info', iconSize: 19, color: Palette.text(this.dark) }).width(28)
          Text(this.t('语言')).fontSize(16).fontColor(Palette.text(this.dark)).layoutWeight(1)
          Select([{ value: this.t('跟随系统') }, { value: this.t('简体中文') }, { value: 'English' }])
            .selected(['system', 'zh-Hans', 'en'].indexOf(this.language))
            .value(this.language === 'system' ? this.t('跟随系统') : this.language === 'en' ? 'English' : this.t('简体中文'))
            .onSelect((index: number) => this.perform(async () => { await settings.setLanguage(['system', 'zh-Hans', 'en'][index]); }))
        }.height(52).padding({ left: 16, right: 16 }).width('100%')
      }.width('100%').borderRadius(24).backgroundColor(Palette.surface(this.dark)).margin({ bottom: 26 })
    }.width('100%')
  }
  private panelTitle(): string {
    switch (this.panel) {
      case 'profile': return this.t('个人资料'); case 'password': return this.session.user?.has_password ? this.t('修改密码') : this.t('设置密码');
      case 'join': return this.t('加入新团队'); case 'rename': return this.t('重命名对话'); case 'delete': return this.t('要删除对话吗？'); default: return this.t('设置');
    }
  }
  @Builder private sheetContent() {
    Stack({ alignContent: Alignment.Center }) {
    if (this.panel === 'profile') {
      ProfileEditor({ session: this.session, onClose: () => this.openPanel('settings'), onBusyChange: (value: boolean) => this.busy = value })
    } else {
    Column({ space: this.panel === 'settings' ? 0 : 12 }) {
      Row() {
        if (['profile', 'password', 'join'].includes(this.panel)) { IconButton({ kind: 'back', label: this.t('返回设置'), glass: false, isEnabled: !this.busy, action: () => this.openPanel('settings') }) }
        Text(this.panelTitle()).fontSize(22).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).layoutWeight(1)
        IconButton({ kind: 'close', label: this.t('关闭'), filled: true, iconSize: 17, isEnabled: !this.busy, action: () => this.sheet = false })
      }.padding({ left: this.panel === 'settings' ? 23 : 20, right: this.panel === 'settings' ? 23 : 20, top: this.panel === 'settings' ? 0 : 6 })
      Scroll() {
        Column({ space: 18 }) {
          if (this.panel === 'settings') { this.settingsContent() }
          else if (this.panel === 'password') {
            if (this.session.user?.has_password) { TextInput({ placeholder: this.t('当前密码'), text: this.oldPassword }).type(InputType.Password).onChange((value: string) => this.oldPassword = value).height(52) }
            TextInput({ placeholder: this.t('新密码（7–16 位）'), text: this.form }).type(InputType.Password).maxLength(16).onChange((value: string) => this.form = value).height(52)
            TextInput({ placeholder: this.t('确认新密码'), text: this.confirmation }).type(InputType.Password).maxLength(16).onChange((value: string) => this.confirmation = value).height(52)
            if (this.form && !validPassword(this.form)) { Text(this.t('新密码长度需为 7 至 16 位')).fontSize(13).fontColor(Palette.error(this.dark)) }
            if (this.confirmation && this.form !== this.confirmation) { Text(this.t('两次输入的新密码不一致')).fontSize(13).fontColor(Palette.error(this.dark)) }
            Button(this.t('保存密码')).enabled(!this.busy && validPassword(this.form) && this.form === this.confirmation && (!this.session.user?.has_password || !!this.oldPassword)).onClick(() => this.submitAccount())
          } else if (this.panel === 'join') {
            Text(this.t('邀请码区分大小写，验证成功后即可加入对应工作空间。')).fontSize(14).fontColor(Palette.secondary(this.dark))
            TextInput({ placeholder: this.t('输入邮件中的邀请码'), text: this.form }).onChange((value: string) => this.form = value).height(52)
            Button(this.t('加入团队')).enabled(!this.busy && !!this.form.trim()).onClick(() => this.submitAccount())
          }
          if (this.busy) { LoadingProgress().width(28).height(28) }
          if (this.sheetError) { Text(this.t(this.sheetError)).fontSize(14).fontColor(Palette.error(this.dark)) }
        }.padding({ left: this.panel === 'settings' ? 23 : 20, right: this.panel === 'settings' ? 23 : 20, bottom: this.panel === 'settings' ? 8 : 32 }).width('100%')
      }.layoutWeight(1).width('100%')
      if (this.panel === 'settings') {
        Row() {
          Button() {
            Row({ space: 8 }) {
              CrestIcon({ kind: 'logout', iconSize: 17, color: Palette.error(this.dark) })
              Text(this.t('退出登录')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Palette.error(this.dark))
            }
          }.height(52).width('100%').borderRadius(45).backgroundColor(Palette.surface(this.dark))
            .enabled(!this.busy)
            .onClick(() => this.perform(async () => { this.chat.close(); await this.session.signOut(); }, true))
        }.width('100%').padding({ left: 23, right: 23, top: 12, bottom: 48 })
      }
    }.width('100%').height('100%').padding({ top: this.panel === 'settings' ? 0 : 8 }).backgroundColor(Palette.glass(this.dark)).backgroundBlurStyle(BlurStyle.Thick)
    }
    if (this.completion) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
      Column({ space: 16 }) {
        Text(this.t(this.completionTitle)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark))
        Text(this.t(this.completionMessage)).fontSize(13).fontColor(Palette.secondary(this.dark)).textAlign(TextAlign.Center)
        Divider().color(Palette.border(this.dark))
        Button(this.completion === 'reauthenticate' ? this.t('重新登录') : this.t('好')).width('100%').backgroundColor(Color.Transparent).fontColor(Palette.accent(this.dark)).onClick(() => this.finishAccount())
      }.padding(20).width(300).borderRadius(24).backgroundColor(Palette.glass(this.dark)).backgroundBlurStyle(BlurStyle.Thick)
    }
    }.width('100%').height('100%')
  }
  @Builder private conversationDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
      Column({ space: 18 }) {
        Column({ space: 6 }) {
          Text(this.panelTitle()).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.text(this.dark))
          Text(this.panel === 'rename' ? this.t('输入新的对话名称') : this.t('这个对话将不再显示在此处，此操作还会从你的活动记录中删除相关的活动记录。'))
            .fontSize(14).fontColor(Palette.secondary(this.dark))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14 })
        if (this.panel === 'rename') {
          TextInput({ text: this.form, placeholder: this.t('对话名称') }).onChange((value: string) => this.form = value)
            .id('conversationName').fontSize(17).height(48).borderRadius(24).padding({ left: 16, right: 16 })
            .backgroundColor(this.dark ? '#303030' : '#E8E8ED').fontColor(Palette.text(this.dark)).enabled(!this.busy)
            .onAppear(() => { setTimeout(() => {
              if (this.dialog && this.panel === 'rename') this.getUIContext().getFocusController().requestFocus('conversationName');
            }, 250); })
        }
        if (this.sheetError) { Text(this.sheetError).fontSize(13).fontColor(Palette.error(this.dark)) }
        if (this.busy) { LoadingProgress().width(24).height(24) }
        Row({ space: 8 }) {
          Button(this.t('取消')).layoutWeight(1).height(48).fontSize(17).fontWeight(FontWeight.Medium)
            .backgroundColor(this.dark ? '#303030' : '#E3E3E8').fontColor(Palette.text(this.dark)).enabled(!this.busy).onClick(() => this.dialog = false)
          Button(this.panel === 'rename' ? this.t('保存') : this.t('确认')).layoutWeight(1).height(48).fontSize(17).fontWeight(FontWeight.Medium)
            .backgroundColor(this.dark ? '#303030' : '#E3E3E8').fontColor(this.panel === 'delete' ? Palette.error(this.dark) : Palette.text(this.dark))
            .enabled(!this.busy && (this.panel === 'delete' || (!!this.form.trim() && this.form.trim() !== this.selected?.title)))
            .onClick(() => this.perform(async () => {
              if (!this.selected) return;
              if (this.panel === 'rename') await this.chat.rename(this.selected, this.form); else await this.chat.delete(this.selected);
            }, true))
        }.width('100%')
      }.padding({ left: 14, right: 14, top: 22, bottom: 14 }).width(320).constraintSize({ maxWidth: '90%' }).borderRadius(36)
        .backgroundColor(this.dark ? '#E6141414' : '#EDF7F7F9').backgroundBlurStyle(BlurStyle.Thick)
        .border({ width: .5, color: this.dark ? '#30FFFFFF' : '#80FFFFFF' })
    }.width('100%').height('100%')
      .onAppear(() => {
        this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
        this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      })
      .onDisAppear(() => this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode))
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.destination === 'chat') { this.chatPage() }
      else if (this.destination === 'analytics') {
        Column() { this.heading(); AnalyticsPage({ session: this.session }).layoutWeight(1) }.width('100%').height('100%')
      } else {
        Column({ space: 10 }) {
          this.heading()
          Search({ value: this.search, placeholder: this.t('搜索对话标题') }).onChange((value: string) => this.search = value).margin({ left: 20, right: 20 })
          this.history(this.chat.sessions.filter((item: Conversation) => item.title.toLowerCase().includes(this.search.trim().toLowerCase())))
        }.width('100%').height('100%')
      }
      if (this.sidebar || this.sidebarDrag > 0) {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .opacity(this.sidebar ? 1 + this.sidebarDrag / this.drawerWidth : this.sidebarDrag / this.drawerWidth)
          .onClick(() => this.settleSidebar(false, 220)).transition(TransitionEffect.OPACITY)
        this.sidebarContent()
      }
      if (this.dialog) { this.conversationDialog() }
    }.width('100%').height('100%').backgroundColor(Palette.background(this.dark))
      .onAreaChange((_old: Area, area: Area) => { this.drawerWidth = Math.max(1, Number(area.width)); })
      .parallelGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart((event: GestureEvent) => this.beginSidebarDrag(event))
        .onActionUpdate((event: GestureEvent) => this.moveSidebarDrag(event))
        .onActionEnd((event: GestureEvent) => this.finishSidebarDrag(event))
        .onActionCancel(() => this.finishSidebarDrag()))
      .bindSheet($$this.sheet, this.sheetContent, { height: this.panel === 'settings' ? '75%' : this.panel === 'profile' ? '96%' : this.panel === 'join' || this.panel === 'password' ? '55%' : '86%', showClose: false, dragBar: false, backgroundColor: Palette.surface(this.dark),
        onWillDismiss: (action: DismissSheetAction) => {
          if (this.busy || this.completion) return;
          if (action.reason === DismissReason.PRESS_BACK) this.back();
          else this.sheet = false;
        },
        onDisappear: () => { this.oldPassword = ''; this.form = ''; this.confirmation = ''; } })
  }
}
