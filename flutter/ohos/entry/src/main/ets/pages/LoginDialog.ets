import { AuthService } from '../platform/AuthService';
import { ConfigManager, UserProfile } from '../platform/ConfigStorage';

@CustomDialog
export struct LoginDialog {
  controller: CustomDialogController;
  @State account: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  onLoginSuccess?: (profile: UserProfile) => void;

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

    const res = await AuthService.login(this.account, this.password);
    this.isLoading = false;

    if (res.success && res.user) {
      if (this.onLoginSuccess) {
        this.onLoginSuccess(res.user);
      }
      this.controller.close();
    } else {
      this.errorMsg = res.message;
    }
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('登录 RustDesk 账号')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
        Blank()
        Button('✕')
          .fontSize(16)
          .fontColor('#86909C')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.controller.close();
          })
      }
      .width('100%')

      Text('登录后可同步远程设备地址簿、共享访问策略与团队设备配置。')
        .fontSize(12)
        .fontColor('#86909C')
        .width('100%')

      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text('账号 / 邮箱')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.account, placeholder: '用户名或注册邮箱' })
            .height(44)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.account = val;
            })
        }

        Column({ space: 4 }) {
          Text('密码')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.password, placeholder: '账户密码' })
            .type(InputType.Password)
            .height(44)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.password = val;
            })
        }
      }
      .width('100%')

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(12)
          .fontColor('#F53F3F')
          .width('100%')
      }

      Button(this.isLoading ? '正在认证...' : '立即登录')
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#007DFF')
        .fontColor('#FFFFFF')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .onClick(() => {
          this.doLogin();
        })
    }
    .width('92%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
  }
}
