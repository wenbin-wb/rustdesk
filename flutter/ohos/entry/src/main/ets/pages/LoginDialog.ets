import { login as accountLogin } from '../platform/AccountService';
import { UserProfile } from '../platform/ConfigStorage';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RustDeskLogin';

@CustomDialog
export struct LoginDialog {
  controller: CustomDialogController;
  @State account: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  onLoginSuccess?: (profile: UserProfile) => void;

  /**
   * Sign in.
   *
   * The loading flag is cleared in a finally block, so a rejection anywhere in the chain --
   * including the profile write that follows a successful login -- cannot leave the button
   * permanently disabled with no explanation. That was the previous behaviour: isLoading
   * stayed true and the dialog showed nothing.
   */
  async doLogin(): Promise<void> {
    if (!this.account.trim()) {
      this.errorMsg = '请输入账号或邮箱';
      return;
    }
    if (!this.password.trim()) {
      this.errorMsg = '请输入密码';
      return;
    }

    this.isLoading = true;
    this.errorMsg = '';

    try {
      const res = await accountLogin(this.account, this.password);
      if (res.success && res.user) {
        if (this.onLoginSuccess) {
          this.onLoginSuccess(res.user);
        }
        this.controller.close();
      } else {
        this.errorMsg = res.message;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'login failed: %{public}s', JSON.stringify(e));
      this.errorMsg = '登录失败，请稍后重试';
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  private field(label: ResourceStr, placeholder: ResourceStr, value: string, isPassword: boolean,
                onText: (v: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize($r('app.float.font_caption'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .height(44)
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.input_text'))
        .placeholderColor($r('app.color.input_placeholder'))
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius($r('app.float.radius_control'))
        .onChange(onText)
    }
    .width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.dialog_login_title'))
          .fontSize($r('app.float.font_subtitle'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Blank()
        Button($r('app.string.common_close'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.controller.close();
          })
      }
      .width('100%')

      Text($r('app.string.dialog_login_hint'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_hint'))
        .width('100%')

      Column({ space: 12 }) {
        this.field($r('app.string.dialog_login_account'),
          $r('app.string.dialog_login_account_placeholder'), this.account, false,
          (v: string) => { this.account = v; })
        this.field($r('app.string.dialog_login_password'),
          $r('app.string.dialog_login_password_placeholder'), this.password, true,
          (v: string) => { this.password = v; })
      }
      .width('100%')

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }

      Button(this.isLoading
        ? $r('app.string.dialog_login_submitting')
        : $r('app.string.dialog_login_submit'))
        .width('100%')
        .height(42)
        .fontSize($r('app.float.font_body'))
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.brand'))
        .fontColor($r('app.color.on_brand'))
        .borderRadius($r('app.float.radius_control'))
        .enabled(!this.isLoading)
        .onClick(() => {
          this.doLogin();
        })
    }
    .width('92%')
    .padding(20)
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius($r('app.float.radius_card'))
  }
}
