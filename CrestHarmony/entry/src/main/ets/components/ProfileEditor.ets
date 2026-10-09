import { localizedFormat } from '../core/Localization';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { LengthMetricsUnit, window } from '@kit.ArkUI';
import { Session } from '../services/Session';
import { ApiError, errorText } from '../services/Api';
import { avatarOrientation, cropRegion } from '../core/Protocol';
import { CrestIcon, IconButton, Palette } from './Theme';

@Component
export struct ProfileEditor {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @ObjectLink session: Session;
  onClose: () => void = () => {};
  onBusyChange: (busy: boolean) => void = () => {};
  @StorageLink('dark') dark: boolean = true;
  @State nickname: string = ''; @State busy: boolean = false; @State error: string = ''; @State notice: string = '';
  @State preview: image.PixelMap | undefined = undefined; @State imageWidth: number = 1; @State imageHeight: number = 1;
  @State zoom: number = 1; @State offsetX: number = 0; @State offsetY: number = 0;
  @State cropping: boolean = false; @State viewport: number = 260;
  @State cropTop: number = 0; @State cropBottom: number = 0;
  private panX: number = 0; private panY: number = 0; private startZoom: number = 1;
  private alive: boolean = false;
  private cropWindow?: window.Window;
  private cropBars?: window.SystemBarProperties;
  private cropBarsTask: Promise<void> = Promise.resolve();
  aboutToAppear(): void { this.alive = true; this.nickname = this.session.displayName; }
  aboutToDisappear(): void { this.alive = false; this.restoreCropBars(); if (!this.busy) this.release(); }
  private setBusy(value: boolean): void { this.busy = value; if (this.alive) this.onBusyChange(value); }
  private canSave(): boolean {
    const length = Array.from(this.nickname.trim()).length;
    return !this.busy && length >= 1 && length <= 30;
  }
  private release(): void {
    this.preview?.release(); this.preview = undefined;
  }
  private async updateCropInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      const host: window.Window = await window.getLastWindow(context);
      if (!this.alive || !this.cropping) return;
      this.cropTop = this.getUIContext().px2vp(host.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
      this.cropBottom = this.getUIContext().px2vp(host.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      if (!this.cropWindow) {
        this.cropBars = host.getWindowSystemBarProperties(); this.cropWindow = host;
        this.cropBarsTask = host.setWindowSystemBarProperties({ statusBarColor: '#000000', statusBarContentColor: '#FFFFFF' });
        await this.cropBarsTask;
        if (!this.alive || !this.cropping) this.restoreCropBars();
      }
    } catch (_) { /* Window may have closed while the cover was appearing. */ }
  }
  private async restoreCropBars(): Promise<void> {
    const host = this.cropWindow; const bars = this.cropBars; const pending = this.cropBarsTask;
    this.cropWindow = undefined; this.cropBars = undefined;
    if (!host || !bars) return;
    // Finish the crop's pending update first so it cannot overwrite the restored page style.
    try { await pending; } catch (_) {}
    try { await host.setWindowSystemBarProperties(bars); } catch (_) { /* Window already closed. */ }
  }
  private async choosePhoto(): Promise<void> {
    if (this.busy) return;
    this.error = ''; this.notice = ''; this.setBusy(true);
    const revision = this.session.revision;
    let source: image.ImageSource | undefined; let file: fs.File | undefined; let decoded: image.PixelMap | undefined;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
      if (!this.alive || revision !== this.session.revision || !result.photoUris.length) return;
      this.release(); file = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY); source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      if (!this.alive || revision !== this.session.revision) return;
      if (info.size.width < 1 || info.size.height < 1) throw new ApiError(0, this.t('无法读取这张图片'));
      const scale = Math.min(1, 2048 / Math.max(info.size.width, info.size.height));
      decoded = await source.createPixelMap({ editable: true, desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale))
      } });
      let orientation = '';
      // Images without EXIF (including PNG screenshots) use their decoded pixel orientation.
      try { orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION); } catch (_) {}
      const transform = avatarOrientation(orientation);
      if (transform[1] || transform[2]) await decoded.flip(transform[1] === 1, transform[2] === 1);
      if (transform[0]) await decoded.rotate(transform[0]);
      const normalized = await decoded.getImageInfo();
      if (!this.alive || revision !== this.session.revision) return;
      this.imageWidth = normalized.size.width; this.imageHeight = normalized.size.height;
      this.preview = decoded; decoded = undefined;
      this.zoom = 1; this.offsetX = 0; this.offsetY = 0;
      this.getUIContext().getFocusController().clearFocus(); this.cropping = true;
    } catch (error) {
      if (this.alive && revision === this.session.revision) { this.release(); this.error = errorText(error as Error); }
    } finally {
      decoded?.release(); source?.release(); if (file) fs.closeSync(file.fd);
      this.setBusy(false); if (!this.alive || revision !== this.session.revision) this.release();
    }
  }
  private clampOffset(): void {
    const min = Math.min(this.imageWidth, this.imageHeight);
    const maxX = (this.viewport * this.imageWidth / min * this.zoom - this.viewport) / 2;
    const maxY = (this.viewport * this.imageHeight / min * this.zoom - this.viewport) / 2;
    this.offsetX = Math.min(maxX, Math.max(-maxX, this.offsetX)); this.offsetY = Math.min(maxY, Math.max(-maxY, this.offsetY));
  }
  private async savePhoto(): Promise<void> {
    if (!this.preview || this.busy || !this.alive) return;
    const revision = this.session.revision;
    this.setBusy(true); this.error = ''; this.notice = '';
    let cropped: image.PixelMap | undefined; const packer = image.createImagePacker();
    try {
      const region = cropRegion(this.imageWidth, this.imageHeight, this.zoom, this.offsetX, this.offsetY, this.viewport);
      // Pixel units keep the output 512×512 on every display density; black flattens PNG alpha like iOS.
      const canvas = new OffscreenCanvasRenderingContext2D(512, 512, new RenderingContextSettings(true), LengthMetricsUnit.PX);
      canvas.fillStyle = '#000000'; canvas.fillRect(0, 0, 512, 512);
      canvas.drawImage(this.preview, region[0], region[1], region[2], region[2], 0, 0, 512, 512);
      cropped = canvas.getPixelMap(0, 0, 512, 512);
      let data: ArrayBuffer | undefined;
      for (const quality of [82, 68, 52]) {
        const candidate = await packer.packing(cropped, { format: 'image/jpeg', quality: quality });
        if (candidate.byteLength <= 1024 * 1024) { data = candidate; break; }
      }
      if (!data) throw new ApiError(0, this.t('无法处理所选图片'));
      if (!this.alive || revision !== this.session.revision) return;
      this.cropping = false;
      await this.session.setAvatar(data);
      if (this.alive && revision === this.session.revision) { this.release(); this.notice = this.t('头像已更新'); }
    } catch (error) { if (this.alive && revision === this.session.revision) this.error = errorText(error as Error); }
    finally { cropped?.release(); packer.release(); this.setBusy(false); if (!this.alive || revision !== this.session.revision) this.release(); }
  }
  private async saveName(): Promise<void> {
    if (!this.canSave()) return;
    const revision = this.session.revision;
    this.setBusy(true); this.error = ''; this.notice = '';
    try {
      await this.session.setName(this.nickname);
      if (this.alive && revision === this.session.revision) { this.setBusy(false); this.onClose(); }
    } catch (error) { if (this.alive && revision === this.session.revision) this.error = errorText(error as Error); }
    finally { this.setBusy(false); }
  }
  @Builder private content() {
    Column({ space: 20 }) {
        Column({ space: 4 }) {
          if (this.session.avatar) { Image(this.session.avatar).width(96).height(96).objectFit(ImageFit.Cover).borderRadius(48) }
          else { Text((this.session.displayName || 'C').slice(0, 1).toUpperCase()).fontSize(34).fontColor(Palette.text(this.dark)).width(96).height(96).textAlign(TextAlign.Center).borderRadius(48).backgroundColor(Palette.field(this.dark)) }
          Button() {
            Row({ space: 10 }) {
              CrestIcon({ kind: 'photo', iconSize: 22, color: Palette.accent(this.dark) })
              Text(this.t('修改头像')).fontSize(17).fontColor(Palette.accent(this.dark))
            }
          }.height(44).backgroundColor(Color.Transparent).accessibilityText(this.t('修改头像')).enabled(!this.busy).onClick(() => { this.choosePhoto(); })
        }.padding({ top: 43, bottom: 0 })
        Column({ space: 8 }) {
          Text(this.t('昵称')).width('100%').padding({ left: 16 }).fontSize(13).fontColor(Palette.secondary(this.dark))
          TextInput({ text: this.nickname, placeholder: this.t('输入昵称') }).height(50).fontSize(17).borderRadius(25).padding({ left: 16, right: 16 })
            .fontColor(Palette.text(this.dark)).backgroundColor(this.dark ? '#2C2C2E' : '#FFFFFF').enabled(!this.busy)
            .onChange((value: string) => this.nickname = value)
          Text(this.t('昵称为 1 至 30 个字符')).width('100%').padding({ left: 16 }).fontSize(12).fontColor(Palette.secondary(this.dark))
        }.width('100%')
      if (this.busy) { LoadingProgress().width(28).height(28).accessibilityText(this.t('保存中…')) }
      if (this.notice) { Text(this.notice).fontSize(14).fontColor(Palette.secondary(this.dark)) }
    }.width('100%').padding({ left: 16, right: 16, bottom: 32 })
  }
  @Builder private cropContent() {
    Stack() {
      Column() {
        Row() {
          Button(this.t('取消')).height(44).width(64).padding({ left: 8, right: 8 }).fontSize(17).fontWeight(FontWeight.Regular).fontColor('#FFFFFF')
            .backgroundColor('#131313').backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.DARK }).border({ width: .5, color: '#28FFFFFF' })
            .enabled(!this.busy).onClick(() => this.cropping = false)
          Text(this.t('调整头像')).layoutWeight(1).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').textAlign(TextAlign.Center)
          Button(this.t('使用')).height(44).width(64).padding({ left: 8, right: 8 }).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .backgroundColor('#131313').backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.DARK }).border({ width: .5, color: '#28FFFFFF' })
            .enabled(!this.busy).onClick(() => this.savePhoto())
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
        Column({ space: 28 }) {
          Blank().layoutWeight(1)
          Stack() {
            if (this.preview) {
              Image(this.preview).objectFit(ImageFit.Fill)
                .width(this.viewport * this.imageWidth / Math.min(this.imageWidth, this.imageHeight) * this.zoom)
                .height(this.viewport * this.imageHeight / Math.min(this.imageWidth, this.imageHeight) * this.zoom)
                .translate({ x: this.offsetX, y: this.offsetY })
            }
          }.width(this.viewport).height(this.viewport).borderRadius(this.viewport / 2).clip(true)
            .border({ width: 1, color: '#E6FFFFFF' }).accessibilityText(this.t('拖动和双指缩放，调整头像位置'))
            .enabled(!this.busy)
            .gesture(GestureGroup(GestureMode.Parallel,
              PanGesture().onActionStart(() => { this.panX = this.offsetX; this.panY = this.offsetY; })
                .onActionUpdate((event: GestureEvent) => { this.offsetX = this.panX + event.offsetX; this.offsetY = this.panY + event.offsetY; this.clampOffset(); }),
              PinchGesture().onActionStart(() => { this.startZoom = this.zoom; })
                .onActionUpdate((event: GestureEvent) => { this.zoom = Math.max(1, Math.min(4, this.startZoom * event.scale)); this.clampOffset(); })
            ))
          Row({ space: 14 }) {
            CrestIcon({ kind: 'zoom-out', iconSize: 20, color: '#FFFFFF' }).accessibilityText(this.t('缩小'))
            Slider({ value: this.zoom, min: 1, max: 4, step: .01 }).layoutWeight(1).selectedColor('#FFFFFF').trackColor('#252525').blockColor('#FFFFFF')
              .enabled(!this.busy).accessibilityText(this.t('头像缩放')).onChange((value: number) => { this.zoom = value; this.clampOffset(); })
            CrestIcon({ kind: 'zoom-in', iconSize: 20, color: '#FFFFFF' }).accessibilityText(this.t('放大'))
          }.width('100%').padding({ left: 24, right: 24 })
          Blank().layoutWeight(1)
        }.width('100%').layoutWeight(1).onAreaChange((_old: Area, area: Area) => {
          this.viewport = Math.max(1, Math.min(Number(area.width) - 32, Number(area.height) - 128)); this.clampOffset();
        })
      }.width('100%').height('100%').padding({ top: this.cropTop, bottom: this.cropBottom }).backgroundColor('#000000')
        .onAreaChange(() => { this.updateCropInsets(); })
      if (this.busy) { LoadingProgress().width(32).height(32).color('#FFFFFF') }
      if (this.error) { this.errorDialog(true) }
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
  @Builder private errorDialog(crop: boolean) {
    Column().width('100%').height('100%').backgroundColor('#66000000')
    Column({ space: 16 }) {
      Text(this.t(crop ? '头像处理失败' : '个人资料修改失败')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.text(crop || this.dark))
      Text(this.t(this.error)).fontSize(13).fontColor(Palette.secondary(crop || this.dark)).textAlign(TextAlign.Center)
      Divider().color(Palette.border(crop || this.dark))
      Button(this.t('好')).width('100%').height(44).backgroundColor(Color.Transparent).fontColor(Palette.accent(crop || this.dark)).onClick(() => this.error = '')
    }.padding(20).width(300).borderRadius(24).backgroundColor(Palette.glass(crop || this.dark)).backgroundBlurStyle(BlurStyle.Thick)
  }
  build() {
    Stack() {
      Column() {
        Row() {
          IconButton({ kind: 'close', label: this.t('取消'), isEnabled: !this.busy, action: () => this.onClose() })
          Text(this.t('个人资料')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).layoutWeight(1).textAlign(TextAlign.Center)
          IconButton({ kind: 'check', label: this.t('保存'), accent: true, isEnabled: this.canSave(), action: () => this.saveName() })
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 8 })
        Scroll() { this.content() }.width('100%').layoutWeight(1).align(Alignment.Top)
      }.width('100%').height('100%').backgroundColor(this.dark ? '#1C1C1E' : '#F2F2F7')
      if (this.error && !this.cropping) { this.errorDialog(false) }
    }.width('100%').height('100%').bindContentCover($$this.cropping, this.cropContent(), {
      backgroundColor: Color.Black,
      onWillDismiss: (action: DismissContentCoverAction) => { if (!this.busy) { this.cropping = false; action.dismiss(); } },
      onDisappear: () => { this.restoreCropBars(); if (!this.busy) this.release(); }
    })
  }
}
