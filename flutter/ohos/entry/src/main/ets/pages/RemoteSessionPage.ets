import { DesktopCanvas } from './DesktopCanvas';
import webview from '@ohos.web.webview';

@Component
export struct RemoteSessionPage {
  @Prop targetId: string = '';
  onDisconnect?: () => void;
  @State showToolbar: boolean = true;
  @State engineMode: string = 'canvas'; // 'canvas' | 'web'
  @State qualityMode: string = '流畅 (Balanced)';
  @State webUrl: string = 'https://rustdesk.com/web';
  private webController: webview.WebviewController = new webview.WebviewController();

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
      } else {
        // High-Fidelity Interactive Native Remote Desktop Canvas
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
            Button(this.engineMode === 'canvas' ? '网页流' : '原生桌面')
              .fontSize(11)
              .height(28)
              .backgroundColor('#33FFFFFF')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .onClick(() => {
                this.engineMode = this.engineMode === 'canvas' ? 'web' : 'canvas';
              })

            // Quality switch
            Button(this.qualityMode.startsWith('流畅') ? '流畅' : '高清')
              .fontSize(11)
              .height(28)
              .backgroundColor('#33FFFFFF')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .onClick(() => {
                this.qualityMode = this.qualityMode.startsWith('流畅') ? '高清 (Best Quality)' : '流畅 (Balanced)';
              })

            // Disconnect Session Button
            Button('断开')
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
        .backgroundColor('#CC1D2129')
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(24)
        .margin({ top: 36 })
        .shadow({ radius: 12, color: '#66000000', offsetX: 0, offsetY: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0F17')
  }
}
