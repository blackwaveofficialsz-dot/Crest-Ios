import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { resolvedLocale } from '../core/Localization';

export class Settings {
  private store?: preferences.Preferences;
  private context?: common.UIAbilityContext;
  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.store = await preferences.getPreferences(context, { name: 'crest.ui' });
    AppStorage.setOrCreate('appearance', await this.store.get('appearance', 'dark') as string);
    AppStorage.setOrCreate('language', await this.store.get('language', 'system') as string);
    this.syncLanguage();
    this.apply();
  }
  async setLanguage(value: string): Promise<void> {
    if (!['system', 'zh-Hans', 'en'].includes(value)) return;
    await this.store?.put('language', value); await this.store?.flush();
    AppStorage.setOrCreate('language', value); this.syncLanguage();
  }
  // Only a non-sensitive logout marker; credentials stay exclusively in Asset Store.
  sessionRestoreBlocked(): boolean {
    if (!this.store) throw new Error('安全退出状态不可用，请重试');
    return this.store.getSync('session.restoreBlocked', false) as boolean;
  }
  async setSessionRestoreBlocked(value: boolean): Promise<void> {
    if (!this.store) throw new Error('安全退出状态不可用，请重试');
    this.store.putSync('session.restoreBlocked', value);
    await this.store.flush();
  }
  lastWorkspace(userId: string): string {
    return this.store?.getSync('lastWorkspace.' + userId, '') as string || '';
  }
  async rememberWorkspace(userId: string, workspaceId: string): Promise<void> {
    if (!userId || !workspaceId || !this.store) return;
    this.store.putSync('lastWorkspace.' + userId, workspaceId);
    await this.store.flush();
  }
  syncLanguage(): void {
    AppStorage.setOrCreate('locale', resolvedLocale(AppStorage.get<string>('language') || 'system', i18n.System.getSystemLanguage()));
  }
  async setMode(value: string): Promise<void> {
    if (!['dark', 'light', 'system'].includes(value)) return;
    await this.store?.put('appearance', value); await this.store?.flush();
    AppStorage.setOrCreate('appearance', value); this.apply();
  }
  private apply(): void {
    const mode = AppStorage.get<string>('appearance') || 'dark';
    const colorMode = mode === 'system' ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET :
      mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    this.context?.getApplicationContext().setColorMode(colorMode);
    AppStorage.setOrCreate('dark', mode === 'system' ? (this.context?.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) : mode === 'dark');
  }
}
export const settings = new Settings();
