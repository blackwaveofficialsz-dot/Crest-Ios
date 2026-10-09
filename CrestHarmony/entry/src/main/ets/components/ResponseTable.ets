import { localizedFormat } from '../core/Localization';
import { Palette } from './Theme';

@Component
export struct ResponseTable {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @Prop title: string = ''; @Prop headers: string[] = []; @Prop rows: string[][] = []; @Prop total: number | undefined = undefined;
  @Prop preview: number = 10; @Prop widths: number[] = [];
  @State expanded: boolean = false;
  @StorageLink('dark') dark: boolean = true;
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  private columns(): number[] {
    const result: number[] = [];
    const count = Math.max(this.headers.length, ...this.rows.map((row: string[]) => row.length));
    for (let i = 0; i < count; i++) result.push(i);
    return result;
  }
  private widthAt(index: number): number { return this.widths[index] || (index === 0 ? 168 : 144); }
  private visibleCount(): number { return this.expanded ? this.rows.length : Math.min(this.preview, this.rows.length); }
  private countLabel(): string {
    return this.t('当前展示 %lld / %lld 行', [String(this.visibleCount()), String(Math.max(this.total ?? this.rows.length, this.rows.length))]);
  }
  private expansionLabel(): string {
    return this.expanded ? this.t('收起') : this.t((this.total ?? this.rows.length) > this.rows.length ? '展开已返回的 %lld 行' : '展开全部（%lld 行）', [String(this.rows.length)]);
  }
  private toggle(): void {
    if (this.reduceMotion) this.expanded = !this.expanded;
    else animateTo({ duration: 200 }, () => this.expanded = !this.expanded);
  }
  @Builder private grid() {
    Scroll() {
      Column() {
        Row() {
          ForEach(this.columns(), (column: number) => {
            Text(this.headers[column] || '').fontSize(15).fontWeight(600).fontColor(Palette.text(this.dark))
              .width(this.widthAt(column)).maxLines(3).padding({ left: 12, right: 12, top: 10, bottom: 10 })
          })
        }.alignItems(VerticalAlign.Top).backgroundColor(Palette.surface(this.dark)).border({ width: { bottom: 1 }, color: Palette.border(this.dark) })
        ForEach(this.expanded ? this.rows : this.rows.slice(0, this.preview), (row: string[], index: number) => {
          Row() {
            ForEach(this.columns(), (column: number) => {
              Text(row[column] ?? '').fontSize(15).fontColor(Palette.text(this.dark)).width(this.widthAt(column))
                .maxLines(3).padding({ left: 12, right: 12, top: 10, bottom: 10 }).copyOption(CopyOptions.InApp)
            })
          }.alignItems(VerticalAlign.Top).border({ width: { bottom: index + 1 < this.visibleCount() ? 1 : 0 }, color: Palette.border(this.dark) })
        })
      }.borderRadius(8).clip(true).backgroundColor(Palette.background(this.dark))
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
  }
  build() {
    Column({ space: 8 }) {
      if (this.title) { Text(this.title).fontSize(15).fontWeight(600).fontColor(Palette.text(this.dark)) }
      this.grid()
      if (this.total !== undefined) {
        Text(this.countLabel())
          .fontSize(12).fontColor(Palette.secondary(this.dark))
      }
      if (this.rows.length > this.preview) {
        Button(this.expansionLabel(), { type: ButtonType.Normal })
          .fontSize(13).fontWeight(FontWeight.Medium).padding({ top: 4, bottom: 4 }).constraintSize({ minHeight: 44 })
          .backgroundColor(Color.Transparent).fontColor(Palette.accent(this.dark))
          .onClick(() => this.toggle())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
