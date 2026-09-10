@CustomDialog
export struct PasswordDialog {
  controller: CustomDialogController;
  targetId: string = '';
  @State passwordInput: string = '';
  @State rememberPassword: boolean = true;
  @State errorMessage: string = '';
  onVerify?: (password: string, remember: boolean) => void;

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('验证远程访问密码')
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

      Text(`安全加密通道已建立，请输入远程设备 [${this.targetId}] 的临时口令或固定密码。`)
        .fontSize(13)
        .fontColor('#4E5969')
        .width('100%')

      Column({ space: 6 }) {
        TextInput({
          text: this.passwordInput,
          placeholder: '输入远程设备密码'
        })
          .type(InputType.Password)
          .height(44)
          .fontSize(15)
          .backgroundColor('#F2F3F5')
          .borderRadius(8)
          .onChange((val: string) => {
            this.passwordInput = val;
            this.errorMessage = '';
          })

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#F53F3F')
            .width('100%')
        }
      }
      .width('100%')

      Row() {
        Checkbox({ name: 'remember', group: 'pwd' })
          .select(this.rememberPassword)
          .selectedColor('#007DFF')
          .onChange((value: boolean) => {
            this.rememberPassword = value;
          })

        Text('记住该设备访问口令')
          .fontSize(13)
          .fontColor('#4E5969')
          .margin({ left: 4 })

        Blank()
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#4E5969')
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
          })

        Button('确认并进入桌面')
          .layoutWeight(1.4)
          .height(42)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#007DFF')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            if (!this.passwordInput.trim()) {
              this.errorMessage = '请输入口令后再进入';
              return;
            }
            if (this.onVerify) {
              this.onVerify(this.passwordInput.trim(), this.rememberPassword);
            }
            this.controller.close();
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('92%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
  }
}
