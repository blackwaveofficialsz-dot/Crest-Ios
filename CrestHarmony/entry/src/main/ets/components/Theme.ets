import { translate } from '../core/Localization';

export class Palette {
  static background(dark: boolean): string { return dark ? '#212121' : '#FFFFFF'; }
  static surface(dark: boolean): string { return dark ? '#2F2F2F' : '#FAFAFA'; }
  static sidebar(dark: boolean): string { return dark ? '#171717' : '#F9F9F9'; }
  static input(dark: boolean): string { return dark ? '#303030' : '#FFFFFF'; }
  static field(dark: boolean): string { return dark ? '#303030' : '#F3F3F3'; }
  static text(dark: boolean): string { return dark ? '#ECECEC' : '#0D0D0D'; }
  static secondary(dark: boolean): string { return dark ? '#B4B4B4' : '#5D5D5D'; }
  static border(dark: boolean): string { return dark ? '#424242' : '#E5E5E5'; }
  static glass(dark: boolean): string { return dark ? '#D92F2F2F' : '#E6FAFAFA'; }
  static accent(dark: boolean): string { return dark ? '#0A84FF' : '#0285FF'; }
  static error(dark: boolean): string { return dark ? '#FF453A' : '#FF3B30'; }
}

@Component
export struct StateMessage {
  @StorageLink('locale') locale: string = 'zh-Hans';
  @Prop title: string = ''; @Prop detail: string = ''; @Prop busy: boolean = false; @Prop action: string = ''; onAction: () => void = () => {};
  @StorageLink('dark') dark: boolean = true;
  build() {
    Column({ space: 14 }) {
      if (this.busy) { LoadingProgress().width(32).height(32).color(Palette.secondary(this.dark)) }
      Text(this.title).fontSize(19).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark))
      if (this.detail) { Text(translate(this.detail, this.locale)).fontSize(14).fontColor(Palette.secondary(this.dark)).textAlign(TextAlign.Center) }
      if (this.action) { Button(this.action).backgroundColor(Palette.text(this.dark)).fontColor(Palette.background(this.dark)).onClick(this.onAction) }
    }.padding(28).width('100%').justifyContent(FlexAlign.Center)
  }
}

export function iconPath(kind: string): string {
  switch (kind) {
    case 'menu': return 'M4 7H20 M4 12H15 M4 17H20';
    case 'edit': return 'M14 4H5V20H20V11 M10 14L11 10L19 2L22 5L14 13Z';
    case 'person': return 'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M12 6A3 3 0 1 0 12 12A3 3 0 1 0 12 6 M5 19C5 12 19 12 19 19';
    case 'close': return 'M6 6L18 18 M18 6L6 18';
    case 'back': return 'M15 5L8 12L15 19';
    case 'eye': return 'M2 12C5 7 8 5 12 5C16 5 19 7 22 12C19 17 16 19 12 19C8 19 5 17 2 12Z M12 9A3 3 0 1 0 12 15A3 3 0 1 0 12 9';
    case 'eye-off': return 'M3 3L21 21 M9 5.5C10 5.2 11 5 12 5C16 5 19 7 22 12C21 13.7 19.7 15.2 18.2 16.4 M15 18.4C14 18.8 13 19 12 19C8 19 5 17 2 12C2.8 10.6 3.8 9.4 5 8.4 M10 10L14 14';
    case 'search': return 'M10 3A7 7 0 1 0 10 17A7 7 0 1 0 10 3 M15 15L21 21';
    case 'zoom-out': return 'M10 3A7 7 0 1 0 10 17A7 7 0 1 0 10 3 M15 15L21 21 M7 10H13';
    case 'zoom-in': return 'M10 3A7 7 0 1 0 10 17A7 7 0 1 0 10 3 M15 15L21 21 M7 10H13 M10 7V13';
    case 'send': return 'M12 19V5 M6 11L12 5L18 11';
    case 'stop': return 'M6 6H18V18H6Z';
    case 'copy': return 'M8 8H20V21H8Z M16 8V3H3V16H8';
    case 'share': return 'M6 9H3V21H21V9H18 M12 15V2 M7 7L12 2L17 7';
    case 'retry': return 'M4 10A8 8 0 1 1 4 16 M4 3V10H11';
    case 'pin': return 'M8 3H16 M9 3V9L6 13H18L15 9V3 M12 13V22';
    case 'trash': return 'M4 6H20 M9 6V3H15V6 M6 6L7 21H17L18 6 M10 10V17 M14 10V17';
    case 'chart': return 'M3 3V21H22 M7 16L12 10L16 13L22 5';
    case 'alert-search': return 'M10 3A7 7 0 1 0 10 17A7 7 0 1 0 10 3 M15 15L21 21 M10 6V10 M10 13V13.2';
    case 'document': return 'M5 2H15L20 7V22H5Z M15 2V7H20 M8 11H17 M8 15H17 M8 19H14';
    case 'menu-card': return 'M4 3H20V21H4Z M8 7H16 M8 11H16 M8 15H13 M8 18H11';
    case 'pie-chart': return 'M12 2V12H22 M10 3A9 9 0 1 0 21 14 M14 2A8 8 0 0 1 22 10H14Z';
    case 'megaphone': return 'M3 10H7L18 5V19L7 14H3Z M7 14L9 20H12L10 15 M20 9C21 11 21 13 20 15';
    case 'check': return 'M4 12L9 17L20 6';
    case 'check-circle': return 'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M7 12L10 15L17 8';
    case 'info': return 'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M12 11V17 M12 7V7.2';
    case 'warning': return 'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M12 6V13 M12 17V17.2';
    case 'error': return 'M8 2H16L22 8V16L16 22H8L2 16V8Z M12 6V13 M12 17V17.2';
    case 'question': return 'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M8.5 8C8.5 4 17 4 15.5 9C15 11 12 11 12 14 M12 17V17.2';
    case 'lightbulb': return 'M8 17C8 13 5 13 5 9A7 7 0 0 1 19 9C19 13 16 13 16 17Z M8 20H16 M10 23H14';
    case 'shield': return 'M12 2L21 6V12C21 17 17 20 12 22C7 20 3 17 3 12V6Z M7 12L10 15L17 8';
    case 'photo': return 'M3 4H21V20H3Z M3 17L9 11L14 16L17 13L21 17 M16 7A2 2 0 1 0 16 11A2 2 0 1 0 16 7';
    case 'sun': return 'M12 7A5 5 0 1 0 12 17A5 5 0 1 0 12 7 M12 1V3 M12 21V23 M1 12H3 M21 12H23 M4 4L5 5 M19 19L20 20 M4 20L5 19 M19 5L20 4';
    case 'key': return 'M8 4A5 5 0 1 0 8 14A5 5 0 1 0 8 4 M12 12L21 21 M16 16L19 13 M19 19L22 16';
    case 'lock': return 'M5 10H19V21H5Z M8 10V7A4 4 0 0 1 16 7V10';
    case 'gear': return 'M10 2H14L14.7 4.3L16.3 5L18.5 4L20.5 6L19.5 8.2L20.2 9.6L22.5 10V14L20.2 14.7L19.5 16.3L20.5 18.5L18.5 20.5L16.3 19.5L14.7 20.2L14 22.5H10L9.3 20.2L7.7 19.5L5.5 20.5L3.5 18.5L4.5 16.3L3.8 14.7L1.5 14V10L3.8 9.3L4.5 7.7L3.5 5.5L5.5 3.5L7.7 4.5L9.3 3.8Z M12 9A3 3 0 1 0 12 15A3 3 0 1 0 12 9';
    case 'team': return 'M9 3A4 4 0 1 0 9 11A4 4 0 1 0 9 3 M2 21V18C2 12 16 12 16 18V21 M17 3C23 3 23 11 17 11 M19 14C22 14 23 17 23 21';
    case 'logout': return 'M10 3H4V21H10 M15 7L20 12L15 17 M20 12H8';
    default: return 'M8 5L15 12L8 19';
  }
}
@Component
export struct CrestIcon {
  @Prop kind: string = 'person'; @Prop iconSize: number = 22; @Prop color: ResourceColor = '#ECECEC';
  build() {
    // Path coordinates are physical pixels; use the same unit for its viewport and stroke.
    Shape() { Path().commands(iconPath(this.kind)).fill(Color.Transparent).stroke(this.color).strokeWidth('1.7px').strokeLineCap(LineCapStyle.Round).strokeLineJoin(LineJoinStyle.Round) }
      .viewPort({ x: 0, y: 0, width: '24px', height: '24px' }).width(this.iconSize).height(this.iconSize)
  }
}
@Component
export struct IconButton {
  @Prop kind: string = 'person'; @Prop label: string = ''; action: () => void = () => {}; @Prop glass: boolean = true; @Prop isEnabled: boolean = true;
  @Prop accent: boolean = false; @Prop filled: boolean = false; @Prop iconSize: number = 22;
  @StorageLink('dark') dark: boolean = true;
  build() {
    Button({ type: ButtonType.Circle }) {
      if (this.glass) {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(36).height(36).fill(this.filled ? (this.isEnabled ? Palette.accent(this.dark) : (this.dark ? '#49494B' : '#E6E6E8')) : Palette.glass(this.dark))
          CrestIcon({ kind: this.kind, iconSize: this.iconSize, color: this.filled ? Color.White : this.accent ? Palette.accent(this.dark) : Palette.text(this.dark) })
        }.width(44).height(44)
      } else {
        CrestIcon({ kind: this.kind, iconSize: this.iconSize, color: this.filled ? Color.White : this.accent ? Palette.accent(this.dark) : Palette.secondary(this.dark) })
      }
    }
      .width(44).height(44).backgroundColor(!this.glass && this.filled ? (this.isEnabled ? Palette.accent(this.dark) : (this.dark ? '#49494B' : '#E6E6E8')) : Color.Transparent)
      .enabled(this.isEnabled)
      .accessibilityText(this.label).onClick(this.action)
  }
}
