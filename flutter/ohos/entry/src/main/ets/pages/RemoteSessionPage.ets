import { DesktopCanvas } from './DesktopCanvas';
import webview from '@ohos.web.webview';
import { ConfigManager, ServerConfig } from '../platform/ConfigStorage';

@Component
export struct RemoteSessionPage {
  @Prop targetId: string = '';
  onDisconnect?: () => void;
  @State showToolbar: boolean = true;
  @State engineMode: string = 'web'; // Default to real Web client connection
  @State qualityMode: string = '流畅 (Balanced)';
  @State webUrl: string = 'https://rustdesk.com/web/';
  @State connectionTips: string = '正在接入远程计算机与中继流...';
  private webController: webview.WebviewController = new webview.WebviewController();
  private serverCfg: ServerConfig = { idServer: '', relayServer: '', apiServer: '', key: '' };
  private rememberedPassword: string = '';

  aboutToAppear(): void {
    const configManager = ConfigManager.getInstance();
    configManager.getServerConfig().then((cfg: ServerConfig) => {
      this.serverCfg = cfg;
      if (cfg.webClientUrl && cfg.webClientUrl.trim().length > 0) {
        this.webUrl = cfg.webClientUrl.trim();
      } else if (cfg.idServer && cfg.idServer.trim().length > 0) {
        // If user configured a custom ID server, default to rustdesk web client which will be injected with their custom server
        this.webUrl = 'https://rustdesk.com/web/';
      } else {
        this.webUrl = 'https://rustdesk.com/web/';
      }
    });

    const rawId = this.targetId.replace(/\s+/g, '');
    configManager.getPeerPassword(rawId).then((pwd: string) => {
      this.rememberedPassword = pwd || '';
    });
  }

  private injectCredentialsAndServer(): void {
    const rawId = this.targetId.replace(/\s+/g, '');
    const pwd = this.rememberedPassword;
    const idServer = this.serverCfg.idServer || '';
    const relayServer = this.serverCfg.relayServer || '';
    const key = this.serverCfg.key || '';

    // Inject configuration into web client localStorage & window context
    const script = `
      (function() {
        try {
          if ('${idServer}'.length > 0) {
            localStorage.setItem('custom-rendezvous-server', '${idServer}');
            localStorage.setItem('relay-server', '${relayServer}');
            localStorage.setItem('key', '${key}');
            if (window.setByName) {
              window.setByName('options', JSON.stringify({
                'custom-rendezvous-server': '${idServer}',
                'relay-server': '${relayServer}',
                'key': '${key}'
              }));
            }
          }
          // Attempt to prefill remote ID and trigger connect if input exists
          const inputs = document.querySelectorAll('input');
          for (let i = 0; i < inputs.length; i++) {
            const input = inputs[i];
            if (input.placeholder && (input.placeholder.includes('ID') || input.placeholder.includes('id'))) {
              input.value = '${rawId}';
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
            }
          }
        } catch(e) {
          console.error('RustDesk injection error:', e);
        }
      })();
    `;

    try {
      this.webController.runJavaScript(script);
    } catch {
      // Ignore if controller not ready
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Main Display Layer
      if (this.engineMode === 'web') {
        Web({ src: this.webUrl, controller: this.webController })
          .width('100%')
          .height('100%')
          .domStorageAccess(true)
          .fileAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .javaScriptAccess(true)
          .backgroundColor('#0B0F17')
          .onPageEnd(() => {
            this.connectionTips = '中继通道建立成功，已加载远端桌面';
            this.injectCredentialsAndServer();
          })
      } else {
        // Native interactive canvas backup
        DesktopCanvas({ targetId: this.targetId })
          .width('100%')
          .height('100%')
      }

      // Top Floating Toolbar (HarmonyOS 7 Floating Capsule)
      if (this.showToolbar) {
        Row() {
          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor('#00B42A')
            Text(this.targetId)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }

          Blank()

          Row({ space: 8 }) {
            // Engine mode toggle
            Button(this.engineMode === 'web' ? '网页流 (当前)' : 'Canvas')
              .fontSize(11)
              .height(28)
              .backgroundColor('rgba(255, 255, 255, 0.2)')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .onClick(() => {
                this.engineMode = this.engineMode === 'web' ? 'canvas' : 'web';
              })

            // Disconnect Session Button
            Button('断开连接')
              .fontSize(12)
              .height(28)
              .backgroundColor('#F53F3F')
              .fontColor('#FFFFFF')
              .borderRadius(6)
              .onClick(() => {
                if (this.onDisconnect) {
                  this.onDisconnect();
                }
              })
          }
        }
        .width('94%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .backgroundColor('rgba(29, 33, 41, 0.85)')
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(24)
        .margin({ top: 36 })
        .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.4)', offsetX: 0, offsetY: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0F17')
  }
}
