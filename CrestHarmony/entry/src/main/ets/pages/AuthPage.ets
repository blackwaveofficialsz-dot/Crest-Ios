import { localizedFormat } from '../core/Localization';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { Session } from '../services/Session';
import { ApiError, AUTH, body, errorText } from '../services/Api';
import { PhoneStatus, Verification, Confirmation, MessageResponse } from '../core/Models';
import { validPhone, validPassword } from '../core/Protocol';
import { LoginBackdrop } from '../components/LoginBackdrop';
import { CrestIcon } from '../components/Theme';
import { TokenStore } from '../services/TokenStore';

interface PendingChallenge { id: string; phone: string; purpose: string; resendAt: number; }

@Component
export struct AuthPage {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @ObjectLink session: Session;
  @State step: string = 'phone'; @State phone: string = ''; @State password: string = '';
  @State code: string = ''; @State nextPassword: string = ''; @State confirmPassword: string = '';
  @State error: string = ''; @State notice: string = ''; @State busy: boolean = false; @State cooldown: number = 0;
  @State passwordVisible: boolean = false; @State nextPasswordVisible: boolean = false; @State confirmPasswordVisible: boolean = false;
  private purpose: string = 'login'; private challenge: string = ''; private challengePhone: string = '';
  private verificationToken: string = ''; private expiresAt: number = 0; private resendAt: number = 0;
  private timer: number = -1; private store?: preferences.Preferences;
  private challengeVault: TokenStore = new TokenStore('crest.verification.v1');
  private alive: boolean = false;
  async aboutToAppear(): Promise<void> {
    this.alive = true;
    try {
      this.store = await preferences.getPreferences(getContext(this), { name: 'crest.auth.cooldown' });
      this.resendAt = await this.store.get('resendAt', 0) as number;
    } catch (_) { /* In-memory cooldown still applies; the server is authoritative. */ }
    try {
      const saved = JSON.parse(this.challengeVault.read()) as PendingChallenge;
      if (saved && saved.resendAt === this.resendAt && saved.resendAt > Date.now() && saved.id &&
        validPhone(saved.phone) && ['login', 'personal_register', 'reset_password'].includes(saved.purpose)) {
        this.challenge = saved.id; this.challengePhone = saved.phone; this.purpose = saved.purpose;
      }
    } catch (_) { /* A failed secure read never falls back to plaintext. */ }
    if (this.alive) { this.tick(); this.timer = setInterval(() => this.tick(), 1000); }
  }
  aboutToDisappear(): void {
    this.alive = false; clearInterval(this.timer); this.password = ''; this.nextPassword = ''; this.confirmPassword = ''; this.verificationToken = ''; this.code = '';
    this.passwordVisible = false; this.nextPasswordVisible = false; this.confirmPasswordVisible = false;
  }
  private tick(): void { this.cooldown = Math.max(0, Math.ceil((this.resendAt - Date.now()) / 1000)); }
  private async saveCooldown(): Promise<void> {
    try { await this.store?.put('resendAt', this.resendAt); await this.store?.flush(); }
    catch (_) { /* Keep the in-memory verification usable if preferences are unavailable. */ }
  }
  private async perform(operation: () => Promise<void>): Promise<void> {
    if (this.busy) return; this.busy = true; this.error = ''; this.notice = '';
    try { await operation(); } catch (error) { this.error = errorText(error as Error); } finally { this.busy = false; }
  }
  private async continuePhone(): Promise<void> {
    if (!validPhone(this.phone)) { this.error = this.t('请输入有效的 11 位手机号'); return; }
    await this.perform(async () => {
      const status = await this.session.api.call<PhoneStatus>(http.RequestMethod.POST, AUTH + 'phone-status', body({ "phone": this.phone, "country_code": '+86', "client_type": 'mobile' }));
      if (status.is_registered && status.has_password) this.step = 'password';
      else await this.requestCode(status.is_registered ? 'login' : 'personal_register');
    });
  }
  private async requestCode(purpose: string): Promise<void> {
    if (this.cooldown > 0) {
      if (this.challenge && this.challengePhone === this.phone && this.purpose === purpose) { this.step = 'code'; return; }
      throw new ApiError(0, this.t('操作频繁，请稍等 %lld 秒后再试。', [String(this.cooldown)]));
    }
    this.purpose = purpose; this.step = 'code'; this.code = '';
    // Persist only a timestamp, never phone numbers or verification credentials.
    this.resendAt = Date.now() + 60000; await this.saveCooldown(); this.tick();
    try {
      const result = await this.session.api.call<Verification>(http.RequestMethod.POST, AUTH + 'verifications', body({ "channel": 'sms', "purpose": purpose, "target": this.phone, "invite_token": '' }));
      this.challenge = result.challenge_id; this.challengePhone = this.phone;
      this.resendAt = Date.now() + Math.max(0, result.resend_after) * 1000;
      await this.saveCooldown(); this.tick();
      try { this.challengeVault.write(JSON.stringify({ id: this.challenge, phone: this.phone, purpose: purpose, resendAt: this.resendAt })); }
      catch (_) { /* Current verification continues in memory without an insecure fallback. */ }
      this.step = 'code'; this.code = ''; this.notice = result.message;
    } catch (error) {
      this.challenge = ''; this.resendAt = 0; this.tick();
      try { this.challengeVault.clear(); } catch (_) {}
      await this.saveCooldown();
      this.step = purpose === 'personal_register' ? 'phone' : 'password'; throw error as Error;
    }
  }
  private async verify(): Promise<void> {
    if (!this.challenge || !/^\d{6}$/.test(this.code)) { this.error = this.t('请输入 6 位验证码'); return; }
    await this.perform(async () => {
      const result = await this.session.api.call<Confirmation>(http.RequestMethod.POST, AUTH + 'verifications/' + encodeURIComponent(this.challenge) + '/confirm', body({ "code": this.code }));
      this.challenge = ''; this.code = '';
      try { this.challengeVault.clear(); } catch (_) {}
      if (this.purpose === 'reset_password') {
        this.verificationToken = result.verification_token; this.expiresAt = Date.now() + result.expires_in * 1000; this.step = 'reset';
      } else {
        await this.session.signIn(this.purpose === 'personal_register' ? 'personal-register' : 'login/code', body({ "verification_token": result.verification_token, "client_type": 'mobile', "device_name": 'crest-harmony' }));
      }
    });
  }
  private async resetPassword(): Promise<void> {
    await this.perform(async () => {
      if (!validPassword(this.nextPassword)) throw new ApiError(0, this.t('新密码需为 7 至 16 位'));
      if (this.nextPassword !== this.confirmPassword) throw new ApiError(0, this.t('两次输入的密码不一致'));
      if (!this.verificationToken || Date.now() >= this.expiresAt) throw new ApiError(0, this.t('重置凭据已失效，请重新验证'));
      const result = await this.session.api.call<MessageResponse>(http.RequestMethod.POST, AUTH + 'reset-password', body({ "verification_token": this.verificationToken, "new_password": this.nextPassword }));
      this.verificationToken = ''; this.nextPassword = ''; this.confirmPassword = ''; this.password = ''; this.step = 'password'; this.notice = result.message;
    });
  }
  private back(): void {
    if (this.busy) return;
    this.error = ''; this.notice = ''; this.password = ''; this.code = ''; this.nextPassword = ''; this.confirmPassword = ''; this.verificationToken = '';
    this.passwordVisible = false; this.nextPasswordVisible = false; this.confirmPasswordVisible = false;
    this.step = this.step === 'password' || this.purpose === 'personal_register' ? 'phone' : 'password';
  }
  private canSubmit(): boolean {
    if (this.busy) return false;
    if (this.step === 'phone') return validPhone(this.phone);
    if (this.step === 'password') return this.password.length > 0;
    if (this.step === 'code') return this.code.length === 6;
    return validPassword(this.nextPassword);
  }
  @Builder private submit(label: string, action: () => void) {
    Button(label).height(52).width('100%').borderRadius(26).backgroundColor('#FFFFFF').fontColor('#121212')
      // Read observed state here; a Builder's by-value boolean would stay at its initial value.
      .fontSize(17).fontWeight(FontWeight.Medium).enabled(this.canSubmit()).opacity(this.canSubmit() ? 1 : .5).onClick(action)
  }
  build() {
    Stack() {
      LoginBackdrop()
      Column() {
        Row() {
          if (this.step !== 'phone') {
            Button({ type: ButtonType.Circle }) { CrestIcon({ kind: 'back', color: '#FFFFFF' }) }
              .width(44).height(44).backgroundColor('#332F2F2F').accessibilityText(this.t('返回')).onClick(() => this.back())
          }
        }.height(56).width('100%')
        Blank().layoutWeight(1)
        Column({ space: 12 }) {
          Text('Crest').fontFamily('CrestRoundedBold').fontSize(48).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Text(this.step === 'phone' ? this.t('让经营，更清晰。') : this.step === 'password' ? this.t('欢迎回来') : this.step === 'code' ? this.t('输入验证码') : this.t('设置新密码'))
            .fontSize(22).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          if (this.step !== 'phone') { Text(this.phone).fontSize(15).fontColor('#B3FFFFFF') }
        }.padding({ bottom: 36 })
        Column({ space: 14 }) {
          if (this.step === 'phone') {
            Row() {
              Text('+86').fontSize(16).fontColor('#FFFFFF').padding({ left: 18, right: 12 })
              TextInput({ text: this.phone, placeholder: this.t('手机号') }).type(InputType.PhoneNumber).maxLength(13)
                .layoutWeight(1).height(52).backgroundColor(Color.Transparent).fontColor('#FFFFFF').placeholderColor('#99FFFFFF')
                .onChange((value: string) => { const digits = value.replace(/\D/g, ''); this.phone = (digits.length > 11 && digits.startsWith('86') ? digits.slice(2) : digits).slice(0, 11); })
            }.backgroundColor('#382F2F2F').backgroundBlurStyle(BlurStyle.Thin).borderRadius(26).border({ width: 1, color: '#33FFFFFF' })
            this.submit(this.t('继续'), () => { this.continuePhone(); })
          } else if (this.step === 'password') {
            Row() {
              TextInput({ text: this.password, placeholder: this.t('密码') }).type(this.passwordVisible ? InputType.Normal : InputType.Password)
                .layoutWeight(1).height(52).maxLength(128).backgroundColor(Color.Transparent).fontColor('#FFFFFF').placeholderColor('#99FFFFFF')
                .onChange((value: string) => this.password = value)
              Button({ type: ButtonType.Circle }) { CrestIcon({ kind: this.passwordVisible ? 'eye-off' : 'eye', iconSize: 18, color: '#AAFFFFFF' }) }
                .width(44).height(44).backgroundColor(Color.Transparent)
                .accessibilityText(this.t(this.passwordVisible ? '隐藏密码' : '显示密码')).onClick(() => this.passwordVisible = !this.passwordVisible)
            }.height(52).backgroundColor('#382F2F2F').backgroundBlurStyle(BlurStyle.Thin).borderRadius(26).border({ width: 1, color: '#33FFFFFF' })
            this.submit(this.t('登录'), () => { this.perform(async () => {
              await this.session.signIn('login', body({ "identifier_type": 'phone', "identifier": this.phone, "password": this.password, "client_type": 'mobile', "device_name": 'crest-harmony' }));
            }); })
            Row() {
              Button(this.t('验证码登录')).backgroundColor(Color.Transparent).fontColor('#FFFFFF').onClick(() => { this.perform(() => this.requestCode('login')); })
              Blank()
              Button(this.t('忘记密码？')).backgroundColor(Color.Transparent).fontColor('#FFFFFF').onClick(() => { this.perform(() => this.requestCode('reset_password')); })
            }.width('100%')
          } else if (this.step === 'code') {
            TextInput({ text: this.code, placeholder: this.t('6 位验证码') }).type(InputType.Number).maxLength(6).height(56)
              .fontSize(24).letterSpacing(12).textAlign(TextAlign.Center).fontColor('#FFFFFF').placeholderColor('#99FFFFFF').backgroundColor('#382F2F2F')
              .onChange((value: string) => { this.code = value.replace(/\D/g, ''); if (this.code.length === 6) this.verify(); })
            this.submit(this.t('验证并继续'), () => { this.verify(); })
            Button(this.cooldown > 0 ? this.t('%@ 秒后重新发送', [String(this.cooldown)]) : this.t('重新发送验证码')).backgroundColor(Color.Transparent).fontColor('#FFFFFF')
              .enabled(this.cooldown === 0 && !this.busy).onClick(() => { this.perform(() => this.requestCode(this.purpose)); })
          } else {
            Row() {
              TextInput({ text: this.nextPassword, placeholder: this.t('新密码（7 至 16 位）') }).type(this.nextPasswordVisible ? InputType.Normal : InputType.Password)
                .layoutWeight(1).height(52).maxLength(16).fontColor('#FFFFFF').backgroundColor(Color.Transparent).onChange((value: string) => this.nextPassword = value)
              Button({ type: ButtonType.Circle }) { CrestIcon({ kind: this.nextPasswordVisible ? 'eye-off' : 'eye', iconSize: 18, color: '#AAFFFFFF' }) }
                .width(44).height(44).backgroundColor(Color.Transparent)
                .accessibilityText(this.t(this.nextPasswordVisible ? '隐藏密码' : '显示密码')).onClick(() => this.nextPasswordVisible = !this.nextPasswordVisible)
            }.height(52).backgroundColor('#382F2F2F').backgroundBlurStyle(BlurStyle.Thin).borderRadius(26).border({ width: 1, color: '#33FFFFFF' })
            Row() {
              TextInput({ text: this.confirmPassword, placeholder: this.t('再次输入新密码') }).type(this.confirmPasswordVisible ? InputType.Normal : InputType.Password)
                .layoutWeight(1).height(52).maxLength(16).fontColor('#FFFFFF').backgroundColor(Color.Transparent).onChange((value: string) => this.confirmPassword = value)
              Button({ type: ButtonType.Circle }) { CrestIcon({ kind: this.confirmPasswordVisible ? 'eye-off' : 'eye', iconSize: 18, color: '#AAFFFFFF' }) }
                .width(44).height(44).backgroundColor(Color.Transparent)
                .accessibilityText(this.t(this.confirmPasswordVisible ? '隐藏密码' : '显示密码')).onClick(() => this.confirmPasswordVisible = !this.confirmPasswordVisible)
            }.height(52).backgroundColor('#382F2F2F').backgroundBlurStyle(BlurStyle.Thin).borderRadius(26).border({ width: 1, color: '#33FFFFFF' })
            this.submit(this.t('重置密码'), () => { this.resetPassword(); })
          }
          if (this.busy) { LoadingProgress().width(24).height(24).color('#FFFFFF') }
          if (this.error) { Text(this.t(this.error)).fontSize(14).fontColor('#FFB4AB').textAlign(TextAlign.Center) }
          if (this.notice) { Text(this.t(this.notice)).fontSize(14).fontColor('#FFFFFF').textAlign(TextAlign.Center) }
        }.width('100%').constraintSize({ maxWidth: 430 })
        Blank().layoutWeight(1)
        Text(this.t('Crest · 餐饮经营助手')).fontSize(12).fontColor('#99FFFFFF').padding({ bottom: 24, top: 12 })
      }.height('100%').width('100%').padding({ left: 24, right: 24 })
    }.backgroundColor('#000000').height('100%').width('100%')
  }
}
