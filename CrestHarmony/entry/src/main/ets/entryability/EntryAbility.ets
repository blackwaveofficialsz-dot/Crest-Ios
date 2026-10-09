import { UIAbility, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window, font } from '@kit.ArkUI';
import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { settings } from '../services/Settings';

export default class EntryAbility extends UIAbility {
  private motionChanged = (enabled: boolean): void => { AppStorage.setOrCreate('reduceMotion', enabled); };
  private syncMotion(): void {
    if (deviceInfo.sdkApiVersion < 23) return;
    try { this.motionChanged(accessibility.isAnimationReduceEnabledSync()); } catch (_) {}
  }
  onCreate(): void {
    AppStorage.setOrCreate('dark', true);
    AppStorage.setOrCreate('appearance', 'dark');
    AppStorage.setOrCreate('language', 'system');
    settings.syncLanguage();
    AppStorage.setOrCreate('foreground', true);
    AppStorage.setOrCreate('reduceMotion', false);
    this.syncMotion();
    if (deviceInfo.sdkApiVersion >= 23) {
      try { accessibility.onAnimationReduceStateChange(this.motionChanged); } catch (_) {}
    }
    font.registerFont({ familyName: 'CrestRounded', familySrc: $rawfile('fonts/rubik_regular.ttf') });
    font.registerFont({ familyName: 'CrestRoundedBold', familySrc: $rawfile('fonts/rubik_bold.ttf') });
  }
  onDestroy(): void {
    if (deviceInfo.sdkApiVersion >= 23) {
      try { accessibility.offAnimationReduceStateChange(this.motionChanged); } catch (_) {}
    }
  }
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
  onForeground(): void { this.syncMotion(); AppStorage.setOrCreate('foreground', true); }
  onBackground(): void { AppStorage.setOrCreate('foreground', false); }
  onConfigurationUpdate(config: Configuration): void {
    settings.syncLanguage();
    if (AppStorage.get<string>('appearance') === 'system' && config.colorMode !== undefined)
      AppStorage.setOrCreate('dark', config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }
}
