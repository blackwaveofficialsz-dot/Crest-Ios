import { localizedFormat } from '../core/Localization';
import { ChartPoint, numberText } from '../core/Analytics';
import { Palette, IconButton } from './Theme';

@Component
struct TrendPlot {
  @StorageLink('locale') @Watch('draw') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @Prop @Watch('draw') points: ChartPoint[] = [];
  @Prop comparisonLabel: string = ''; @Prop chartHeight: number = 210;
  @State selected: number = -1;
  @StorageLink('dark') @Watch('draw') dark: boolean = true;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private draw(): void {
    if (!this.ready) return;
    const ctx = this.context; const width = ctx.width, height = ctx.height;
    ctx.clearRect(0, 0, width, height);
    const values: number[] = [];
    this.points.forEach((point: ChartPoint) => {
      if (point.value !== undefined && Number.isFinite(point.value)) values.push(point.value);
      if (point.comparison !== undefined && Number.isFinite(point.comparison)) values.push(point.comparison);
    });
    if (!values.length) return;
    const min = Math.min(0, ...values), max = Math.max(1, ...values), span = max - min || 1;
    const left = 54, right = width - 12, top = 15, bottom = height - 26;
    ctx.font = '11px sans-serif'; ctx.strokeStyle = Palette.border(this.dark); ctx.fillStyle = Palette.secondary(this.dark); ctx.lineWidth = .5;
    for (let index = 0; index <= 3; index++) {
      const y = top + (bottom - top) * index / 3;
      ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke();
      const value = max - span * index / 3;
      ctx.fillText(Math.abs(value) >= 10000 ? (this.locale === 'en' ? `${(value / 1000).toFixed(0)}K` : `${(value / 10000).toFixed(1)}万`) : value.toFixed(0), 0, y + 4);
    }
    for (let series = 0; series < 2; series++) {
      ctx.strokeStyle = series === 0 ? Palette.accent(this.dark) : Palette.secondary(this.dark); ctx.lineWidth = 2; ctx.beginPath(); let connected = false;
      this.points.forEach((point: ChartPoint, index: number) => {
        const value = series === 0 ? point.value : point.comparison;
        if (value === undefined || !Number.isFinite(value)) { connected = false; return; }
        const x = left + (right - left) * index / Math.max(1, this.points.length - 1), y = bottom - ((value - min) / span) * (bottom - top);
        if (connected) ctx.lineTo(x, y); else ctx.moveTo(x, y);
        connected = true;
      }); ctx.stroke();
    }
    if (this.selected >= 0 && this.selected < this.points.length) {
      const x = left + (right - left) * this.selected / Math.max(1, this.points.length - 1);
      ctx.strokeStyle = Palette.secondary(this.dark); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
    }
    ctx.fillStyle = Palette.secondary(this.dark);
    if (this.points.length) { ctx.fillText(this.points[0].label.slice(5), left, height - 5); ctx.fillText(this.points[this.points.length - 1].label.slice(5), Math.max(left, right - 38), height - 5); }
  }
  build() {
    Column({ space: 8 }) {
      Canvas(this.context).width('100%').height(this.chartHeight).onReady(() => { this.ready = true; this.draw(); }).onAreaChange(() => this.draw())
        .onTouch((event: TouchEvent) => {
          if (!event.touches.length || !this.points.length) return;
          this.selected = Math.max(0, Math.min(this.points.length - 1, Math.round((event.touches[0].x - 54) / Math.max(1, this.context.width - 66) * (this.points.length - 1))));
          this.draw();
        })
        .accessibilityText(this.points.map((point: ChartPoint) => `${point.label}：${numberText(point.value)}`).join('；'))
      if (this.selected >= 0 && this.points[this.selected]) {
        Text(this.points[this.selected].label + ' · ' + numberText(this.points[this.selected].value) +
          (this.comparisonLabel ? ' / ' + this.comparisonLabel + ' ' + numberText(this.points[this.selected].comparison) : ''))
          .fontSize(13).fontColor(Palette.text(this.dark)).padding(8).backgroundColor(Palette.surface(this.dark)).borderRadius(8)
      }
      if (this.comparisonLabel) { Text(this.t('实际') + ' / ' + this.comparisonLabel).fontSize(12).fontColor(Palette.secondary(this.dark)) }
      if (!this.points.length) { Text(this.t('暂无趋势数据')).fontSize(13).fontColor(Palette.secondary(this.dark)) }
      if (this.points.some((point: ChartPoint) => point.value === undefined)) { Text(this.t('缺失日期保留断点，不补零')).fontSize(11).fontColor(Palette.secondary(this.dark)) }
    }.width('100%')
  }
}

@Component
export struct TrendChart {
  @Prop points: ChartPoint[] = []; @Prop comparisonLabel: string = '';
  @StorageLink('dark') dark: boolean = true;
  @StorageLink('locale') locale: string = 'zh-Hans';
  @State expanded: boolean = false;
  @Builder private fullScreen() {
    Column({ space: 20 }) {
      Row() {
        Text(localizedFormat('趋势图', this.locale, [])).fontSize(20).fontColor(Palette.text(this.dark)).layoutWeight(1)
        IconButton({ kind: 'close', label: localizedFormat('关闭详情', this.locale, []), action: () => this.expanded = false })
      }.width('100%')
      Scroll() { TrendPlot({ points: this.points, comparisonLabel: this.comparisonLabel, chartHeight: 400 }) }.layoutWeight(1)
    }.padding(24).width('100%').height('100%').backgroundColor(Palette.background(this.dark))
  }
  build() {
    Column({ space: 6 }) {
      Row() {
        Blank()
        Button(localizedFormat('展开图表', this.locale, [])).fontSize(12).backgroundColor(Color.Transparent).fontColor(Palette.accent(this.dark)).onClick(() => this.expanded = true)
      }.width('100%')
      TrendPlot({ points: this.points, comparisonLabel: this.comparisonLabel })
    }.width('100%').bindContentCover($$this.expanded, this.fullScreen)
  }
}
