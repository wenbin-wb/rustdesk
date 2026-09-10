import { FlutterPage } from './FlutterPage';

@Preview
@Entry
@Component
struct Index {
  @State isFlutterReady: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isFlutterReady) {
        FlutterPage({ viewId: 'flutter_view' })
          .width('100%')
          .height('100%')
      } else {
        Column({ space: 16 }) {
          Image($r('app.media.icon'))
            .width(80)
            .height(80)
            .borderRadius(16)
            .shadow({ radius: 12, color: '#20000000', offsetX: 0, offsetY: 4 })

          Text('RustDesk')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2329')

          Text('开源远程桌面 · 鸿蒙版')
            .fontSize(14)
            .fontColor('#646A73')

          Column({ space: 10 }) {
            Row() {
              Text('运行环境')
                .fontSize(13)
                .fontColor('#8F959E')
              Blank()
              Text('HarmonyOS NEXT (API 26)')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1F2329')
            }
            .width('100%')

            Divider().color('#E5E6EB')

            Row() {
              Text('核心架构')
                .fontSize(13)
                .fontColor('#8F959E')
              Blank()
              Text('Flutter-OHOS + Rust FFI')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1F2329')
            }
            .width('100%')

            Divider().color('#E5E6EB')

            Row() {
              Text('引擎状态')
                .fontSize(13)
                .fontColor('#8F959E')
              Blank()
              Text('已就绪')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#007DFF')
            }
            .width('100%')
          }
          .width('85%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 2 })
          .margin({ top: 20 })

          Button('进入远程桌面')
            .fontSize(14)
            .backgroundColor('#007DFF')
            .width('85%')
            .height(44)
            .borderRadius(8)
            .margin({ top: 16 })
            .onClick(() => {
              this.isFlutterReady = true;
            })

          Text('提示：在模拟器或真机中点击可进入 Flutter 渲染视窗')
            .fontSize(12)
            .fontColor('#8F959E')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F7FA')
      }
    }
    .width('100%')
    .height('100%')
  }
}
