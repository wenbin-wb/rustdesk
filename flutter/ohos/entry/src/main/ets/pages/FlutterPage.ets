@Component
export struct FlutterPage {
  @Prop viewId: string = 'flutter_view';

  build() {
    Stack() {
      XComponent({ id: this.viewId, type: XComponentType.SURFACE })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
