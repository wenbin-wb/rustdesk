import { ConfigManager, ServerConfig } from '../platform/ConfigStorage';

/**
 * Self-hosted / relay server settings.
 *
 * Every colour comes from a resource token so the dialog follows dark mode. That matters
 * here more than elsewhere: a TextInput whose background is a fixed light grey while the
 * placeholder colour follows the system theme produces light text on a light field in dark
 * mode, which is unreadable. Both the background and the placeholder come from tokens now.
 *
 * The values are an @Link to the page's own state rather than something this dialog reads
 * for itself. When it read on aboutToAppear the fields came up empty on reopen: the dialog
 * instance is tied to its controller, which is a member of the page, so the read happened
 * once, before the core and preferences were ready, and never again. The page now loads the
 * configuration and then opens the dialog, so what is shown is always what was loaded.
 */
@CustomDialog
export struct ServerSettingsDialog {
  controller: CustomDialogController;
  /** Owned by the page; edited here and saved back through ConfigManager. */
  @Link serverCfg: ServerConfig;
  @State statusMsg: string = '';
  onSaved?: () => void;

  private async saveConfig(): Promise<void> {
    const cfg: ServerConfig = {
      idServer: this.serverCfg.idServer.trim(),
      relayServer: this.serverCfg.relayServer.trim(),
      apiServer: this.serverCfg.apiServer.trim(),
      key: this.serverCfg.key.trim(),
      webClientUrl: (this.serverCfg.webClientUrl || '').trim()
    };
    await ConfigManager.getInstance().saveServerConfig(cfg);
    this.serverCfg = cfg;
    if (this.onSaved) {
      this.onSaved();
    }
    this.controller.close();
  }

  @Builder
  private field(label: ResourceStr, placeholder: ResourceStr, value: string,
                onText: (v: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize($r('app.float.font_caption'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .height(42)
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
    Column({ space: 14 }) {
      Row() {
        Text($r('app.string.dialog_server_title'))
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

      Text($r('app.string.dialog_server_hint'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_hint'))
        .width('100%')

      Column({ space: 10 }) {
        this.field($r('app.string.dialog_server_id'), 'custom.rustdesk.com', this.serverCfg.idServer,
          (v: string) => { this.serverCfg.idServer = v; })
        this.field($r('app.string.dialog_server_relay'), 'relay.example.com', this.serverCfg.relayServer,
          (v: string) => { this.serverCfg.relayServer = v; })
        this.field($r('app.string.dialog_server_api'), 'http://custom.rustdesk.com:21114', this.serverCfg.apiServer,
          (v: string) => { this.serverCfg.apiServer = v; })
        this.field($r('app.string.dialog_server_key'), 'Base64', this.serverCfg.key,
          (v: string) => { this.serverCfg.key = v; })
      }
      .width('100%')

      if (this.statusMsg.length > 0) {
        Text(this.statusMsg)
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }

      Row({ space: 12 }) {
        Button($r('app.string.dialog_server_reset'))
          .layoutWeight(1)
          .height(40)
          .fontSize($r('app.float.font_body'))
          .backgroundColor($r('app.color.bg_subtle'))
          .fontColor($r('app.color.text_body'))
          .borderRadius($r('app.float.radius_control'))
          .onClick(() => {
            // Clearing the fields restores the core's built-in default, which is the public
            // servers; save is still what applies it.
            this.serverCfg = {
              idServer: '',
              relayServer: '',
              apiServer: '',
              key: '',
              webClientUrl: ''
            };
          })

        Button($r('app.string.dialog_server_save'))
          .layoutWeight(1)
          .height(40)
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.brand'))
          .fontColor($r('app.color.on_brand'))
          .borderRadius($r('app.float.radius_control'))
          .onClick(() => {
            this.saveConfig();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('92%')
    .padding(20)
    .backgroundColor($r('app.color.dialog_bg'))
    .borderRadius($r('app.float.radius_card'))
  }
}
