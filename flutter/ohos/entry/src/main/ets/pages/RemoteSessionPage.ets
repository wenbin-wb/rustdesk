import { FlutterPage } from './FlutterPage';
import { DesktopCanvas } from './DesktopCanvas';

@Component
export struct RemoteSessionPage {
  @Prop targetId: string = '';
  onDisconnect?: () => void;
  @State showToolbar: boolean = true;
  @State isSoftKeyboardVisible: boolean = false;
  @State qualityMode: string = '流畅 (Balanced)';
  @State latencyMs: number = 24;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Interactive Remote Stream Canvas with live touch input
      DesktopCanvas({ targetId: this.targetId })
        .width('100%')
        .height('100%')

      // Top Floating Toolbar (Matches iOS/Android Remote Control Bar)
      if (this.showToolbar) {
        Row() {
          Row({ space: 8 }) {
            Circle({ width: 8, height: 8 }).fill('#00B42A')
            Text(this.targetId)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }

          Blank()

          Row({ space: 8 }) {
            // Quality / Resolution switch
            Button(this.qualityMode)
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
        .borderRadius(24)
        .margin({ top: 32 })
        .shadow({ radius: 8, color: '#44000000', offsetX: 0, offsetY: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
