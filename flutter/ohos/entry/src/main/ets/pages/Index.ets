import { FlutterPage } from '@ohos/flutter_ohos';

@Entry
@Component
struct Index {
  @State isFlutterReady: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底层：Flutter 原生渲染视窗
      FlutterPage({ viewId: 'flutter_view' })
        .width('100%')
        .height('100%')

      // 2. 预览占位与品牌启动卡片（在 IDE Previewer 静态预览及引擎初始化时展示）
      if (!this.isFlutterReady) {
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

          Text('提示：完整交互式远程桌面请在模拟器或真机中运行')
            .fontSize(12)
            .fontColor('#8F959E')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F7FA')
        .onClick(() => {
          this.isFlutterReady = true;
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
