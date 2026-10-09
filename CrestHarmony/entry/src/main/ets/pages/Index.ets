import { localizedFormat } from '../core/Localization';
import { common } from '@kit.AbilityKit';
import { Session } from '../services/Session';
import { settings } from '../services/Settings';
import { StateMessage, Palette } from '../components/Theme';
import { AuthPage } from './AuthPage';
import { HomePage } from './HomePage';

@Entry
@Component
struct Index {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @State session: Session = new Session();
  @StorageLink('dark') dark: boolean = true;
  private backHandler: () => boolean = () => false;
  onBackPress(): boolean { return this.backHandler(); }
  async aboutToAppear(): Promise<void> {
    try { await settings.init(getContext(this) as common.UIAbilityContext); }
    catch (_) { /* Restore reports persistence errors without exposing the account. */ }
    await this.session.restore();
  }
  build() {
    Column() {
      if (this.session.state === 'clearing') {
        StateMessage({ title: this.t('正在退出登录'), busy: true }).layoutWeight(1)
      } else if (this.session.state === 'cleanupError') {
        StateMessage({ title: this.t('退出未完成'), detail: this.t(this.session.error), action: this.t('重试'), onAction: () => { this.session.restore(); } }).layoutWeight(1)
      } else if (this.session.state === 'restoring') {
        StateMessage({ title: this.t('正在恢复登录状态'), busy: true }).layoutWeight(1)
      } else if (this.session.state === 'restoreError') {
        StateMessage({ title: this.t('无法恢复登录'), detail: this.t(this.session.error), action: this.t('重试'), onAction: () => { this.aboutToAppear(); } }).layoutWeight(1)
      } else if (this.session.state === 'signedIn') {
        HomePage({ session: this.session, registerBack: (handler: () => boolean) => { this.backHandler = handler; } })
      } else {
        AuthPage({ session: this.session })
      }
    }.width('100%').height('100%').backgroundColor(Palette.background(this.dark))
  }
}
