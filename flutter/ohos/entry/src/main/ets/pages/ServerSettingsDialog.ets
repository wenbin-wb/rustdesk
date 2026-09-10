import { ConfigManager, ServerConfig } from '../platform/ConfigStorage';

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
    const configManager = ConfigManager.getInstance();
    configManager.getServerConfig().then((cfg: ServerConfig) => {
      this.idServer = cfg.idServer;
      this.relayServer = cfg.relayServer;
      this.apiServer = cfg.apiServer;
      this.publicKey = cfg.key;
      this.webClientUrl = cfg.webClientUrl || '';
    });
  }

  async saveConfig(): Promise<void> {
    const configManager = ConfigManager.getInstance();
    const cfg: ServerConfig = {
      idServer: this.idServer.trim(),
      relayServer: this.relayServer.trim(),
      apiServer: this.apiServer.trim(),
      key: this.publicKey.trim(),
      webClientUrl: this.webClientUrl.trim()
    };
    await configManager.saveServerConfig(cfg);
    if (this.onSaved) {
      this.onSaved();
    }
    this.controller.close();
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('ID / 中继服务器设置')
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

      Text('支持连接官方网络或自建 RustDesk Server。留空则恢复默认官方服务器。')
        .fontSize(12)
        .fontColor('#86909C')
        .width('100%')

      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text('ID 服务器 (ID Server)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.idServer, placeholder: '如: custom.rustdesk.com' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.idServer = val;
            })
        }

        Column({ space: 4 }) {
          Text('中继服务器 (Relay Server)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.relayServer, placeholder: '留空将默认复用 ID 服务器' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.relayServer = val;
            })
        }

        Column({ space: 4 }) {
          Text('API 服务器 (API Server)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.apiServer, placeholder: '如: http://custom.rustdesk.com:21114' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.apiServer = val;
            })
        }

        Column({ space: 4 }) {
          Text('公钥 Key (可选)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.publicKey, placeholder: '服务器 public key (Base64)' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.publicKey = val;
            })
        }

        Column({ space: 4 }) {
          Text('网页客户端/控制台 URL (可选)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
            .width('100%')
          TextInput({ text: this.webClientUrl, placeholder: '如: http://ip:21118 或留空自动适配' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F2F3F5')
            .borderRadius(6)
            .onChange((val: string) => {
              this.webClientUrl = val;
            })
        }
      }
      .width('100%')

      if (this.statusMsg.length > 0) {
        Text(this.statusMsg)
          .fontSize(12)
          .fontColor('#F53F3F')
          .width('100%')
      }

      Row({ space: 12 }) {
        Button('重置默认')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .fontColor('#4E5969')
          .borderRadius(6)
          .onClick(() => {
            this.idServer = '';
            this.relayServer = '';
            this.apiServer = '';
            this.publicKey = '';
          })

        Button('保存配置')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#007DFF')
          .fontColor('#FFFFFF')
          .borderRadius(6)
          .onClick(() => {
            this.saveConfig();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('92%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
  }
}
