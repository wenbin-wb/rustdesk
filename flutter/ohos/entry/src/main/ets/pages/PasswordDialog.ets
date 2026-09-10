@CustomDialog
export struct PasswordDialog {
  controller: CustomDialogController;

  /**
   * The peer being authorised, linked to the page's state.
   *
   * This has to be @Link, not a plain member. The dialog instance is created once per
   * controller and reused for every open, and a plain member is only read when the instance is
   * built -- so the dialog would show an empty target on the first open and the *previous*
   * peer on later ones, while the flow itself authorised whichever peer was actually chosen.
   * The user would then be typing peer A's password for peer B.
   *
   * @Watch clears the typed password and any error when the target changes, so a value entered
   * for one peer cannot be carried over and remembered against another.
   */
  @Link @Watch('onTargetChanged') targetId: string;
  @State passwordInput: string = '';
  @State rememberPassword: boolean = true;
  @State errorMessage: string = '';
  onVerify?: (password: string, remember: boolean) => void;

  onTargetChanged(): void {
    this.reset();
  }

  /**
   * Clear the fields every time the dialog is shown.
   *
   * @Watch only fires on a change, so reopening for the same peer -- which is the common case --
   * would otherwise leave the previously typed password on screen and let a second tap
   * resubmit it unnoticed. The instance is reused across opens, so this has to be reset
   * explicitly rather than relying on construction defaults.
   */
  aboutToAppear(): void {
    this.reset();
  }

  private reset(): void {
    this.passwordInput = '';
    this.errorMessage = '';
    this.rememberPassword = true;
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text($r('app.string.dialog_password_title'))
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

      Text($r('app.string.dialog_password_hint'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text(this.targetId)
        .fontSize($r('app.float.font_subtitle'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand'))
        .width('100%')

      Column({ space: 6 }) {
        TextInput({
          text: this.passwordInput,
          placeholder: $r('app.string.dialog_password_placeholder')
        })
          .type(InputType.Password)
          .height(44)
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.input_text'))
          .placeholderColor($r('app.color.input_placeholder'))
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius($r('app.float.radius_control'))
          .onChange((val: string) => {
            this.passwordInput = val;
            this.errorMessage = '';
          })

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
      }
      .width('100%')

      Row() {
        Checkbox({ name: 'remember', group: 'pwd' })
          .select(this.rememberPassword)
          .selectedColor($r('app.color.brand'))
          .onChange((value: boolean) => {
            this.rememberPassword = value;
          })

        Text($r('app.string.dialog_password_remember'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_body'))
          .margin({ left: 4 })

        Blank()
      }
      .width('100%')

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(42)
          .fontSize($r('app.float.font_body'))
          .backgroundColor($r('app.color.bg_subtle'))
          .fontColor($r('app.color.text_body'))
          .borderRadius($r('app.float.radius_control'))
          .onClick(() => {
            this.controller.close();
          })

        Button($r('app.string.devices_connect'))
          .layoutWeight(1.4)
          .height(42)
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_brand'))
          .borderRadius($r('app.float.radius_control'))
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
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius($r('app.float.radius_card'))
  }
}
