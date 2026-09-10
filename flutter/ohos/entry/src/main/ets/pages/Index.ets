import { FlutterPage } from './FlutterPage';

interface DeviceItem {
  id: string;
  name: string;
  os: string;
  online: boolean;
}

@Preview
@Entry
@Component
struct Index {
  @State isFlutterReady: boolean = false;
  @State activeTab: number = 0;
  @State remoteIdInput: string = '';
  @State myId: string = '952 831 406';
  @State oneTimePassword: string = 'rk82mf';
  @State connectionStatus: string = '就绪 (Ready)';
  @State isConnecting: boolean = false;
  @State recentDevices: DeviceItem[] = [
    { id: '189 423 881', name: '办公电脑 - Windows 11', os: 'Windows', online: true },
    { id: '402 119 532', name: 'MacBook Pro M2', os: 'macOS', online: true },
    { id: '773 205 914', name: 'Ubuntu Server (CI)', os: 'Linux', online: false }
  ];

  formatId(input: string): string {
    const raw = input.replace(/\s+/g, '');
    const chunks: string[] = [];
    for (let i = 0; i < raw.length; i += 3) {
      chunks.push(raw.substring(i, Math.min(i + 3, raw.length)));
    }
    return chunks.join(' ');
  }

  connectToPeer(targetId: string): void {
    if (!targetId.trim()) {
      this.connectionStatus = '请输入远程设备 ID';
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = '正在发起握手: ' + targetId + '...';
    setTimeout(() => {
      this.connectionStatus = '等待对方接受或验证密码...';
      setTimeout(() => {
        this.connectionStatus = '模拟连接成功! [加密通道已建立]';
        this.isConnecting = false;
      }, 1000);
    }, 800);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isFlutterReady) {
        FlutterPage({ viewId: 'flutter_view' })
          .width('100%')
          .height('100%')
      } else {
        Column() {
          Row() {
            Image($r('app.media.icon'))
              .width(28)
              .height(28)
              .borderRadius(6)
              .margin({ right: 8 })

            Text('RustDesk')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1F2329')

            Blank()

            Row({ space: 6 }) {
              Circle({ width: 8, height: 8 })
                .fill('#00B42A')
              Text('网络就绪')
                .fontSize(12)
                .fontColor('#00B42A')
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#E8FFEA')
            .borderRadius(12)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 4, color: '#0A000000', offsetX: 0, offsetY: 2 })

          Scroll() {
            Column({ space: 16 }) {
              if (this.activeTab === 0) {
                this.buildConnectionTab()
              } else if (this.activeTab === 1) {
                this.buildDevicesTab()
              } else {
                this.buildSettingsTab()
              }
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .width('100%')

          Row() {
            this.buildNavItem('连接', 0)
            this.buildNavItem('设备', 1)
            this.buildNavItem('设置', 2)
          }
          .width('100%')
          .height(56)
          .backgroundColor('#FFFFFF')
          .border({ width: { top: 1 }, color: '#E5E6EB' })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F7FA')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildNavItem(title: string, index: number) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === index ? '#007DFF' : '#8F959E')
      if (this.activeTab === index) {
        Divider()
          .strokeWidth(2)
          .color('#007DFF')
          .width(20)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.activeTab = index;
    })
  }

  @Builder
  buildConnectionTab() {
    Column({ space: 14 }) {
      Column({ space: 10 }) {
        Row() {
          Text('本机 ID 与密码')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
          Blank()
          Text('允许控制')
            .fontSize(12)
            .fontColor('#00B42A')
        }
        .width('100%')

        Divider().color('#F2F3F5')

        Row() {
          Column({ space: 4 }) {
            Text('你的设备 ID')
              .fontSize(12)
              .fontColor('#86909C')
            Text(this.myId)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1D2129')
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Column({ space: 4 }) {
            Text('一次性密码')
              .fontSize(12)
              .fontColor('#86909C')
            Text(this.oneTimePassword)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 8, color: '#08000000', offsetX: 0, offsetY: 2 })

      Column({ space: 12 }) {
        Text('控制远程桌面')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
          .width('100%')

        TextInput({
          placeholder: '输入远程设备 ID (例: 189 423 881)',
          text: this.remoteIdInput
        })
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .borderRadius(8)
          .backgroundColor('#F2F3F5')
          .onChange((val: string) => {
            this.remoteIdInput = this.formatId(val);
          })

        Row({ space: 10 }) {
          Button('发起连接')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#007DFF')
            .borderRadius(8)
            .enabled(!this.isConnecting)
            .onClick(() => {
              this.connectToPeer(this.remoteIdInput);
            })

          Button('传输文件')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#F2F3F5')
            .fontColor('#1D2129')
            .borderRadius(8)
            .onClick(() => {
              if (!this.remoteIdInput.trim()) {
                this.connectionStatus = '请先输入远程 ID 后传输文件';
                return;
              }
              this.connectionStatus = '已准备向 ' + this.remoteIdInput + ' 发起文件传输通道...';
            })
        }
        .width('100%')

        Row() {
          Text(this.connectionStatus)
            .fontSize(12)
            .fontColor(this.isConnecting ? '#007DFF' : '#4E5969')
            .width('100%')
        }
        .padding(10)
        .backgroundColor('#F7F8FA')
        .borderRadius(6)
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 8, color: '#08000000', offsetX: 0, offsetY: 2 })

      Column({ space: 8 }) {
        Text('快捷填充测试 ID')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#4E5969')
          .width('100%')

        Row({ space: 8 }) {
          ForEach(this.recentDevices, (device: DeviceItem) => {
            Button(device.os)
              .fontSize(12)
              .height(32)
              .backgroundColor('#E8F3FF')
              .fontColor('#007DFF')
              .borderRadius(16)
              .onClick(() => {
                this.remoteIdInput = device.id;
                this.connectionStatus = '已选定: ' + device.name + ' (' + device.id + ')';
              })
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
    }
    .width('100%')
  }

  @Builder
  buildDevicesTab() {
    Column({ space: 10 }) {
      Row() {
        Text('最近连接设备 (' + this.recentDevices.length + ')')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
        Blank()
        Text('+ 发现局域网')
          .fontSize(13)
          .fontColor('#007DFF')
      }
      .width('100%')
      .margin({ bottom: 4 })

      ForEach(this.recentDevices, (device: DeviceItem) => {
        Row() {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Circle({ width: 8, height: 8 })
                .fill(device.online ? '#00B42A' : '#C9CDD4')
              Text(device.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1D2129')
            }
            Text('ID: ' + device.id + ' · ' + device.os)
              .fontSize(12)
              .fontColor('#86909C')
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Button('连接')
            .fontSize(12)
            .height(30)
            .backgroundColor('#007DFF')
            .borderRadius(6)
            .onClick(() => {
              this.activeTab = 0;
              this.remoteIdInput = device.id;
              this.connectToPeer(device.id);
            })
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .shadow({ radius: 4, color: '#06000000', offsetX: 0, offsetY: 1 })
      })
    }
    .width('100%')
  }

  @Builder
  buildSettingsTab() {
    Column({ space: 12 }) {
      Text('环境与桥接状态')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D2129')
        .width('100%')

      Column({ space: 10 }) {
        this.buildSettingItem('系统版本', 'HarmonyOS NEXT (API 26)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('屏幕采集', 'AVScreenCapture (就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('剪贴板同步', 'Pasteboard API 12+ (就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('文件管理器', 'CoreFileKit (就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('Flutter 视窗', 'XComponent SURFACE')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)

      Button('进入全量 Flutter 视窗')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#007DFF')
        .borderRadius(8)
        .margin({ top: 12 })
        .onClick(() => {
          this.isFlutterReady = true;
        })

      Text('注：在云电脑等纯预览模式下，可在此完整体验 RustDesk 交互流程。')
        .fontSize(12)
        .fontColor('#86909C')
        .margin({ top: 4 })
    }
    .width('100%')
  }

  @Builder
  buildSettingItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#4E5969')
      Blank()
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D2129')
    }
    .width('100%')
  }
}
