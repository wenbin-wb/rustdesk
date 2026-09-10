export interface TabItemData {
  title: string;
  iconResource: Resource;
}

@Component
export struct LiquidTabBar {
  @Link activeIndex: number;
  private tabs: TabItemData[] = [
    { title: '远程连接', iconResource: $r('app.media.tab_remote') },
    { title: '设备簿', iconResource: $r('app.media.tab_devices') },
    { title: '系统设置', iconResource: $r('app.media.tab_settings') }
  ];
  onTabChange?: (index: number) => void;

  build() {
    Row() {
      ForEach(this.tabs, (item: TabItemData, index: number) => {
        Stack() {
          // Liquid Pill Background for active item with spring glow & fluid gradient
          if (this.activeIndex === index) {
            Column()
              .width('100%')
              .height('100%')
              .borderRadius(22)
              .linearGradient({
                angle: 135,
                colors: [['#1F007DFF', 0.0], ['#2E007DFF', 1.0]]
              })
              .border({ width: 1, color: '#40007DFF' })
              .shadow({ radius: 12, color: '#33007DFF', offsetY: 2 })
              .animation({
                duration: 250,
                curve: Curve.Friction
              })
          }

          Column({ space: 3 }) {
            Image(item.iconResource)
              .width(20)
              .height(20)
              .fillColor(this.activeIndex === index ? '#007DFF' : '#86909C')
              .scale({
                x: this.activeIndex === index ? 1.08 : 1.0,
                y: this.activeIndex === index ? 1.08 : 1.0
              })
              .animation({
                duration: 200,
                curve: Curve.EaseInOut
              })

            Text(item.title)
              .fontSize(11)
              .fontWeight(this.activeIndex === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.activeIndex === index ? '#007DFF' : '#86909C')
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .height('100%')
        }
        .layoutWeight(1)
        .height(48)
        .borderRadius(22)
        .margin({ left: 3, right: 3 })
        .onClick(() => {
          this.activeIndex = index;
          if (this.onTabChange) {
            this.onTabChange(index);
          }
        })
      })
    }
    .width('92%')
    .height(64)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor('#B3FFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(32)
    .border({ width: 0.8, color: '#80FFFFFF' })
    .shadow({
      radius: 28,
      color: '#1A000000',
      offsetX: 0,
      offsetY: 8
    })
  }
}
