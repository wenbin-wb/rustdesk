export interface TabItemData {
  title: string;
  badgeCount?: number;
}

@Component
export struct LiquidTabBar {
  @Link activeIndex: number;
  private tabs: TabItemData[] = [
    { title: '远程连接' },
    { title: '设备簿' },
    { title: '系统设置' }
  ];
  onTabChange?: (index: number) => void;

  build() {
    Row() {
      ForEach(this.tabs, (item: TabItemData, index: number) => {
        Stack() {
          // Liquid Selected Background Capsule
          if (this.activeIndex === index) {
            Column()
              .width('100%')
              .height('100%')
              .borderRadius(24)
              .backgroundColor('#1A007DFF')
              .border({ width: 1, color: '#4D007DFF' })
              .shadow({ radius: 12, color: '#33007DFF', offsetY: 2 })
              .animation({
                duration: 260,
                curve: Curve.FastOutSlowIn
              })
          }

          Row({ space: 6 }) {
            // Indicator Dot / Icon simulation
            Circle({ width: 6, height: 6 })
              .fill(this.activeIndex === index ? '#007DFF' : '#8F959E')

            Text(item.title)
              .fontSize(14)
              .fontWeight(this.activeIndex === index ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.activeIndex === index ? '#007DFF' : '#64748B')
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height('100%')
        }
        .layoutWeight(1)
        .height(44)
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
    .height(58)
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .backgroundColor('#D9FFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(29)
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({
      radius: 24,
      color: '#1A000000',
      offsetX: 0,
      offsetY: 8
    })
  }
}
