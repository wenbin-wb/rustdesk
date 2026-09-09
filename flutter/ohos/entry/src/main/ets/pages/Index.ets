import { FlutterPage } from '@ohos/flutter_ohos';

@Entry
@Component
struct Index {
  build() {
    Column() {
      FlutterPage({ viewId: 'flutter_view' })
    }
    .width('100%')
    .height('100%')
  }
}
