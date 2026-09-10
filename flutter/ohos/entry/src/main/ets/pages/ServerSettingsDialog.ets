import { ConfigManager, ServerConfig } from '../platform/ConfigStorage';

/**
 * Self-hosted / relay server settings.
 *
 * Every colour comes from a resource token so the dialog follows dark mode. That matters
 * here more than elsewhere: a TextInput whose background is a fixed light grey while the
 * placeholder colour follows the system theme produces light text on a light field in dark
 * mode, which is unreadable. Both the background and the placeholder come from tokens now.
 */
@CustomDialog
export struct ServerSettingsDialog {
  controller: CustomDialogController;
  @State idServer: string = '';
  @State relayServer: string = '';
  @State apiServer: string = '';
  @State publicKey: string = '';
  @State webClientUrl: string = '';
  @State statusMsg: string = '';
  onSaved?: () => void;

  aboutToAppear(): void {
    ConfigManager.getInstance().getServerConfig().then((cfg: ServerConfig) => {
      this.idServer = cfg.idServer;
      this.relayServer = cfg.relayServer;
      this.apiServer = cfg.apiServer;
      this.publicKey = cfg.key;
      this.webClientUrl = cfg.webClientUrl || '';
    });
  }

  /**
   * Persist to the app store and hand the same values to the core.
   *
   * The core keeps its own configuration and is what actually talks to the network, so
   * writing only to the ArkTS store would leave the running core on the public servers --
   * the save would appear to work and change nothing. ConfigManager owns the core handoff.
   */
  private async saveConfig(): Promise<void> {
    const cfg: ServerConfig = {
      idServer: this.idServer.trim(),
      relayServer: this.relayServer.trim(),
      apiServer: this.apiServer.trim(),
      key: this.publicKey.trim(),
      webClientUrl: this.webClientUrl.trim()
    };
    await ConfigManager.getInstance().saveServerConfig(cfg);
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
        this.field($r('app.string.dialog_server_id'), 'custom.rustdesk.com', this.idServer,
          (v: string) => { this.idServer = v; })
        this.field($r('app.string.dialog_server_relay'), 'relay.example.com', this.relayServer,
          (v: string) => { this.relayServer = v; })
        this.field($r('app.string.dialog_server_api'), 'http://custom.rustdesk.com:21114', this.apiServer,
          (v: string) => { this.apiServer = v; })
        this.field($r('app.string.dialog_server_key'), 'Base64', this.publicKey,
          (v: string) => { this.publicKey = v; })
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
            this.idServer = '';
            this.relayServer = '';
            this.apiServer = '';
            this.publicKey = '';
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
