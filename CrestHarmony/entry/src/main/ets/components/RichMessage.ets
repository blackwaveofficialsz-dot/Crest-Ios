import { localizedFormat } from '../core/Localization';
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MarkdownBlockCache, inline, Block, Inline } from '../core/Markdown';
import { safeLink } from '../core/Protocol';
import { ChatMessage, ResponsePart, ResponseMetric, ResponseAction, Insight } from '../core/Models';
import { formatMetric, metricRows, tableHeaders, tableRows, tableWidths, responseStatus } from '../core/ResponseFormat';
import { Palette, IconButton, CrestIcon } from './Theme';
import { ResponseTable } from './ResponseTable';
import { copyText, shareText } from '../services/MessageActions';

@Component
struct InlineText {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @Prop value: string = ''; @Prop textSize: number = 17; @Prop bold: boolean = false;
  @Prop secondary: boolean = false; @Prop streaming: boolean = false;
  @StorageLink('dark') dark: boolean = true;
  build() {
    Text() {
      ForEach(inline(this.value), (part: Inline) => {
        Span(part.text).fontWeight(part.bold ? FontWeight.Bold : this.bold ? 600 : FontWeight.Normal)
          .fontStyle(part.italic ? FontStyle.Italic : FontStyle.Normal).fontFamily(part.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(part.link && safeLink(part.link) ? Palette.accent(this.dark) : this.secondary ? Palette.secondary(this.dark) : Palette.text(this.dark))
          .decoration({ type: part.strike ? TextDecorationType.LineThrough : part.link ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (safeLink(part.link)) {
              const context = getContext(this) as common.UIAbilityContext;
              context.startAbility({ action: 'ohos.want.action.viewData', uri: part.link }).catch(() => { this.getUIContext().getPromptAction().showToast({ message: this.t('无法打开链接') }); });
            }
          })
      })
    }.fontSize(this.textSize).lineSpacing(LengthMetrics.fp(5)).copyOption(this.streaming ? CopyOptions.None : CopyOptions.InApp).width('100%')
  }
}
@Component
struct MarkdownCodeBlock {
  @Prop code: string = ''; @Prop language: string = ''; @Prop streaming: boolean = false;
  @StorageLink('dark') dark: boolean = true;
  @StorageLink('locale') locale: string = 'zh-Hans';
  @State copied: boolean = false;
  private timer: number = -1;
  aboutToDisappear(): void { clearTimeout(this.timer); }
  private t(key: string): string { return localizedFormat(key, this.locale, []); }
  private async copy(): Promise<void> {
    try {
      await copyText(this.code); this.copied = true; clearTimeout(this.timer);
      this.timer = setTimeout(() => this.copied = false, 1400);
    } catch (_) { this.getUIContext().getPromptAction().showToast({ message: this.t('复制失败') }); }
  }
  build() {
    Column() {
      Row() {
        Text(this.language || this.t('代码')).fontSize(12).fontColor(Palette.secondary(this.dark)).layoutWeight(1)
        IconButton({ kind: this.copied ? 'check' : 'copy', label: this.copied ? this.t('已复制') : this.t('复制代码'), iconSize: 13, glass: false, action: () => this.copy() })
      }.padding({ left: 12, right: 5 }).constraintSize({ minHeight: 38 })
      Divider().color(Palette.border(this.dark))
      Scroll() { Text(this.code || ' ').fontFamily('monospace').fontSize(14).lineSpacing(LengthMetrics.fp(3)).fontColor(Palette.text(this.dark)).copyOption(this.streaming ? CopyOptions.None : CopyOptions.InApp).padding(12) }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }.backgroundColor(Palette.surface(this.dark)).borderRadius(8).border({ width: 1, color: Palette.border(this.dark) }).clip(true).width('100%')
  }
}
@Component
export struct MarkdownView {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @Prop @Watch('refreshBlocks') text: string = ''; @Prop @Watch('refreshBlocks') streaming: boolean = false;
  @State blocks: Block[] = [];
  private cache: MarkdownBlockCache = new MarkdownBlockCache();
  @StorageLink('dark') dark: boolean = true;
  aboutToAppear(): void { this.refreshBlocks(); }
  private refreshBlocks(): void { this.cache.update(this.text, this.streaming); this.blocks = this.cache.blocks; }
  build() {
    Column({ space: 14 }) {
      ForEach(this.blocks, (block: Block) => {
        if (block.kind === 'heading') {
          InlineText({ value: block.text, textSize: block.level === 1 ? 20 : block.level === 2 ? 18 : 17, bold: true, streaming: this.streaming })
            .padding({ top: block.level === 1 ? 10 : block.level === 2 ? 8 : 6, bottom: 2 })
        }
        else if (block.kind === 'code') {
          MarkdownCodeBlock({ code: block.text, language: block.language, streaming: this.streaming })
        } else if (block.kind === 'table') {
          if (this.streaming) {
            Scroll() {
              Text([block.headers].concat(block.rows).map((row: string[]) => '| ' + row.join(' | ') + ' |').join('\n'))
                .fontFamily('monospace').fontSize(14).fontColor(Palette.text(this.dark)).padding(12)
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
              .backgroundColor(Palette.surface(this.dark)).borderRadius(8).clip(true).border({ width: 1, color: Palette.border(this.dark) })
          } else { ResponseTable({ headers: block.headers, rows: block.rows, preview: 10 }) }
        }
        else if (block.kind === 'list' || block.kind === 'ordered') {
          Column({ space: 8 }) {
            ForEach(block.items, (item: string, index: number) => {
              Row({ space: 8 }) {
                Text(block.kind === 'ordered' ? `${block.start + index}.` : '•').fontSize(17).fontColor(Palette.secondary(this.dark)).width(24).textAlign(TextAlign.End)
                InlineText({ value: item, streaming: this.streaming }).layoutWeight(1)
              }.alignItems(VerticalAlign.Top).width('100%')
            })
          }.width('100%')
        } else if (block.kind === 'quote') {
          Row() { InlineText({ value: block.text, secondary: true, streaming: this.streaming }) }
            .padding({ left: 14, top: 4, bottom: 4 }).border({ width: { left: 3 }, color: '#8C' + Palette.secondary(this.dark).slice(1) }).width('100%')
        } else if (block.kind === 'divider') { Divider().color(Palette.border(this.dark)) }
        else { InlineText({ value: block.text, streaming: this.streaming }) }
      })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
@Component
struct ThinkingWave {
  @StorageLink('foreground') @Watch('updateActivity') foreground: boolean = true;
  @StorageLink('reduceMotion') @Watch('updateActivity') reduceMotion: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timer: number = -1;
  private ready: boolean = false;
  aboutToDisappear(): void { this.ready = false; this.stop(); }
  private stop(): void { if (this.timer >= 0) clearInterval(this.timer); this.timer = -1; }
  private updateActivity(): void {
    this.stop();
    if (!this.ready) return;
    if (this.reduceMotion) { this.draw(0.22); return; }
    if (this.foreground) this.timer = setInterval(() => this.draw((Date.now() / 1000 % 1.8) / 1.8), 33);
  }
  private draw(progress: number): void {
    const c = this.context, w = c.width, h = c.height;
    if (!w || !h) return;
    c.reset();
    c.lineCap = 'round'; c.lineJoin = 'round';
    const phase = progress * Math.PI * 2;
    for (let ribbon = -1; ribbon < 3; ribbon++) {
      c.beginPath();
      for (let x = 0; x <= w; x += 1) {
        const normalized = x / w;
        const taper = 0.42 + Math.sin(normalized * Math.PI) * 0.58;
        const y = h / 2 + (ribbon < 0 ? 0 : (ribbon - 1) * 2.5) * taper + Math.sin(normalized * 2.25 * Math.PI + phase) * 4.2;
        if (x === 0) c.moveTo(x, y); else c.lineTo(x, y);
      }
      c.strokeStyle = ribbon < 0 ? 'rgba(255,255,255,0.96)' : 'rgba(0,0,0,0.86)';
      c.lineWidth = ribbon < 0 ? 9 : 0.85;
      c.stroke();
    }
  }
  build() {
    Canvas(this.context).width(48).height(24).hitTestBehavior(HitTestMode.None)
      .onReady(() => { this.ready = true; this.draw(this.reduceMotion ? 0.22 : (Date.now() / 1000 % 1.8) / 1.8); this.updateActivity(); })
  }
}
@Component
export struct RichMessage {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @Prop message: ChatMessage = new ChatMessage('', 'assistant', '');
  @Prop streaming: boolean = false; @Prop stage: string = ''; @Prop canAct: boolean = true;
  onRetry: () => void = () => {}; onAction: (action: ResponseAction) => void = () => {}; onApproval: (decision: string) => void = () => {};
  @StorageLink('dark') dark: boolean = true;
  @State copied: boolean = false;
  private copyTimer: number = -1;
  private alive: boolean = false;
  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; clearTimeout(this.copyTimer); }
  private toast(text: string): void { this.getUIContext().getPromptAction().showToast({ message: text }); }
  private showFooter(): boolean { return !this.streaming && !this.message.error && this.message.content.trim().length > 0; }
  private showStatus(): boolean { return !this.streaming && !this.message.error && responseStatus(this.message.status).length > 0; }
  private async copyReply(): Promise<void> {
    try {
      await copyText(this.message.content);
      if (!this.alive) return;
      clearTimeout(this.copyTimer); this.copied = true; this.toast(this.t('已复制到剪贴板'));
      this.copyTimer = setTimeout(() => this.copied = false, 3000);
    } catch (_) { if (this.alive) this.toast(this.t('复制失败')); }
  }
  private async shareReply(): Promise<void> {
    try { await shareText(getContext(this) as common.UIAbilityContext, this.message.content); }
    catch (_) { if (this.alive) this.toast(this.t('未能打开分享面板')); }
  }
  private noticeColor(severity: string = ''): string {
    return severity === 'error' ? Palette.error(this.dark) : severity === 'warning' ? '#FF9F0A' : Palette.accent(this.dark);
  }
  @Builder private part(part: ResponsePart) {
    if (part.kind === 'table') {
      ResponseTable({ title: part.title || '', headers: tableHeaders(part), rows: tableRows(part, this.locale), total: part.row_count, preview: 3, widths: tableWidths(part) })
    } else if (part.kind === 'notice') {
      Row({ space: 10 }) {
        CrestIcon({ kind: part.severity === 'error' ? 'error' : 'info', iconSize: 18, color: this.noticeColor(part.severity) })
        Column({ space: 4 }) {
          if (part.title) { Text(part.title).fontSize(15).fontWeight(600).fontColor(Palette.text(this.dark)).width('100%') }
          if (part.message) { Text(part.message).fontSize(15).fontColor(Palette.secondary(this.dark)).width('100%') }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.alignItems(VerticalAlign.Top).padding(14).width('100%').borderRadius(14)
        .backgroundColor('#14' + this.noticeColor(part.severity).slice(1)).border({ width: 1, color: '#33' + this.noticeColor(part.severity).slice(1) })
    } else {
      Column({ space: part.kind === 'insights' ? 10 : part.kind === 'clarification' ? 6 : 12 }) {
        if (part.title) { Text(part.title).fontSize(17).fontWeight(600).fontColor(Palette.text(this.dark)).width('100%') }
        if (part.message) {
          Text(part.message).fontSize(part.kind === 'clarification' ? 17 : 15)
            .fontColor(part.kind === 'clarification' ? Palette.text(this.dark) : Palette.secondary(this.dark)).width('100%')
        }
        if (part.kind === 'summary') {
          ForEach(metricRows(part.metrics || []), (row: ResponseMetric[]) => {
            Row({ space: 12 }) {
              ForEach(row, (metric: ResponseMetric) => {
                Column({ space: 3 }) {
                  Text(metric.label || metric.key).fontSize(12).fontColor(Palette.secondary(this.dark)).width('100%')
                  Text(formatMetric(metric, this.locale)).fontSize(17).fontWeight(600).fontColor(Palette.text(this.dark)).width('100%')
                }.layoutWeight(1)
              })
              if (row.length === 1) { Blank().layoutWeight(1) }
            }.width('100%').alignItems(VerticalAlign.Top)
          })
        }
        if (part.kind === 'insights') {
          ForEach(part.items || [], (item: Insight) => {
            Row({ space: 9 }) {
              CrestIcon({ kind: item.statement_type === 'recommendation' ? 'lightbulb' : item.statement_type === 'hypothesis' ? 'question' : 'check-circle',
                iconSize: 18, color: item.statement_type === 'recommendation' ? '#FF9F0A' : Palette.accent(this.dark) })
              Text(item.text).fontSize(15).fontColor(Palette.text(this.dark)).layoutWeight(1)
            }.alignItems(VerticalAlign.Top).width('100%')
          })
        }
      }.alignItems(HorizontalAlign.Start).padding(14).width('100%').borderRadius(14).backgroundColor(Palette.surface(this.dark))
        .border({ width: 1, color: Palette.border(this.dark) })
    }
  }
  build() {
    Column({ space: 6 }) {
      if (this.message.role === 'user') {
        Row() {
          Blank().width(54)
          Text(this.message.content).fontSize(17).fontColor(Palette.text(this.dark)).copyOption(CopyOptions.InApp)
            .padding({ left: 15, right: 15, top: 11, bottom: 11 }).borderRadius(18).backgroundColor(Palette.surface(this.dark))
        }.justifyContent(FlexAlign.End).width('100%')
      } else {
        if (this.showStatus()) {
          Row({ space: 4 }) {
            CrestIcon({ kind: 'warning', iconSize: 12, color: this.message.status === 'failed' ? Palette.error(this.dark) : '#FF9F0A' })
            Text(this.t(responseStatus(this.message.status))).fontSize(12).fontWeight(600)
              .fontColor(this.message.status === 'failed' ? Palette.error(this.dark) : '#FF9F0A')
          }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(20)
            .backgroundColor('#17' + (this.message.status === 'failed' ? Palette.error(this.dark) : '#FF9F0A').slice(1))
            .accessibilityText(this.t('分析结果：%@', [this.t(responseStatus(this.message.status))]))
        }
        if (this.message.error) {
          Column({ space: 10 }) {
            Row({ space: 6 }) {
              CrestIcon({ kind: 'warning', iconSize: 15, color: Palette.error(this.dark) })
              Text(this.t('回答生成失败')).fontSize(15).fontWeight(600).fontColor(Palette.error(this.dark))
            }
            Text(this.t(this.message.error)).fontSize(15).fontColor(Palette.secondary(this.dark))
            if (this.message.errorCode) { Text(this.message.errorCode).fontSize(12).fontFamily('monospace').fontColor(Palette.secondary(this.dark)) }
            if (this.message.retryable) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  CrestIcon({ kind: 'retry', iconSize: 15, color: Palette.error(this.dark) })
                  Text(this.t('重新提问')).fontSize(15).fontColor(Palette.error(this.dark))
                }
              }.padding({ left: 12, right: 12 }).height(44).borderRadius(8).backgroundColor('#0FFF453A')
                .border({ width: 1, color: '#38FF453A' }).enabled(this.canAct && !this.streaming).onClick(this.onRetry)
            }
          }.alignItems(HorizontalAlign.Start).padding(14).width('100%').borderRadius(14).backgroundColor('#0FFF453A').border({ width: 1, color: '#38FF453A' })
        } else if (this.message.content) { MarkdownView({ text: this.message.content, streaming: this.streaming }) }
        else if (this.streaming) {
          ThinkingWave().width(48).height(24)
            .accessibilityText(this.stage ? this.t(this.stage) : this.t('正在回复'))
        }
        if (!this.streaming) { ForEach(this.message.parts, (part: ResponsePart) => { this.part(part) }) }
        if (this.message.status === 'cancelled') { Text(this.t('已停止回复')).fontSize(12).fontColor(Palette.secondary(this.dark)).width('100%') }
        if (!this.streaming && this.message.actions.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.message.actions, (action: ResponseAction) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 8 }) {
                  Text(action.label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Palette.accent(this.dark)).maxLines(2).layoutWeight(1).textAlign(TextAlign.Start)
                  CrestIcon({ kind: 'forward', iconSize: 12, color: Palette.accent(this.dark) })
                }.width('100%')
              }.padding({ left: 14, right: 14, top: 11, bottom: 11 }).width('100%').constraintSize({ minHeight: 44 }).borderRadius(12)
                .backgroundColor('#14' + Palette.accent(this.dark).slice(1)).border({ radius: 12, width: 1, color: '#33' + Palette.accent(this.dark).slice(1) })
                .enabled(this.canAct).onClick(() => this.onAction(action))
            })
          }.width('100%').padding({ top: 4 })
        }
        if (this.message.approval) {
          Column({ space: 12 }) {
            Row({ space: 6 }) {
              CrestIcon({ kind: 'shield', iconSize: 15, color: Palette.text(this.dark) })
              Text(this.message.approval.tool_label).fontSize(15).fontWeight(600).fontColor(Palette.text(this.dark))
            }
            Text(this.message.approval.message).fontSize(15).fontColor(Palette.secondary(this.dark))
            Row({ space: 12 }) {
              Button(this.t('拒绝')).backgroundColor('#0FFF453A').fontColor(Palette.error(this.dark)).enabled(this.canAct && !this.streaming).onClick(() => this.onApproval('reject'))
              Button(this.t('确认执行')).backgroundColor(Palette.accent(this.dark)).fontColor(Color.White).enabled(this.canAct && !this.streaming).onClick(() => this.onApproval('approve'))
            }
          }.alignItems(HorizontalAlign.Start).padding(14).width('100%').backgroundColor(Palette.surface(this.dark)).borderRadius(14).border({ width: 1, color: Palette.border(this.dark) })
        }
        if (this.showFooter()) {
          Row() {
            IconButton({ kind: this.copied ? 'check' : 'copy', label: this.copied ? this.t('已复制') : this.t('复制回复'), iconSize: 15, accent: this.copied, glass: false, action: () => this.copyReply() })
            IconButton({ kind: 'share', label: this.t('分享回复'), iconSize: 15, glass: false, action: () => this.shareReply() })
            IconButton({ kind: 'retry', label: this.t('重新生成回复'), iconSize: 15, glass: false, isEnabled: this.canAct, action: this.onRetry })
          }.width('100%').padding({ top: 4 })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
