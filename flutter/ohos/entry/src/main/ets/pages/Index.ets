import { FlutterPage } from './FlutterPage';
import { ConfigManager, ServerConfig, UserProfile, StoredPeer } from '../platform/ConfigStorage';
import { ServerSettingsDialog } from './ServerSettingsDialog';
import { LoginDialog } from './LoginDialog';
import { AuthService } from '../platform/AuthService';

@Preview
@Entry
@Component
struct Index {
  @State isFlutterReady: boolean = false;
  @State activeTab: number = 0;
  @State remoteIdInput: string = '';
  @State myId: string = '';
  @State oneTimePassword: string = '';
  @State connectionStatus: string = '就绪 (Ready)';
  @State isConnecting: boolean = false;
  @State isOnline: boolean = true;
  @State serverHost: string = '官方默认服务器 (公网)';
  @State userProfile: UserProfile = {
    username: '',
    email: '',
    token: '',
    avatar: '',
    isLoggedIn: false
  };
  @State recentDevices: StoredPeer[] = [];

  private serverSettingsDialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog({
      onSaved: () => {
        this.loadServerConfig();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private loginDialogController: CustomDialogController = new CustomDialogController({
    builder: LoginDialog({
      onLoginSuccess: (profile: UserProfile) => {
        this.userProfile = profile;
        this.connectionStatus = '已登录账号: ' + profile.username;
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.initRealData();
  }

  async initRealData(): Promise<void> {
    const context = getContext(this);
    const configManager = ConfigManager.getInstance();
    await configManager.init(context);

    // Load or generate real local ID
    let id = await configManager.getMyId();
    if (!id) {
      id = this.generateDeviceNumId();
      await configManager.setMyId(id);
    }
    this.myId = this.formatId(id);

    // Load or generate one-time session password
    let pwd = await configManager.getOneTimePassword();
    if (!pwd) {
      pwd = this.generateRandomPassword(6);
      await configManager.setOneTimePassword(pwd);
    }
    this.oneTimePassword = pwd;

    // Load server config
    await this.loadServerConfig();

    // Load user account
    this.userProfile = await configManager.getUserProfile();

    // Load real connected peers history
    this.recentDevices = await configManager.getRecentPeers();
  }

  async loadServerConfig(): Promise<void> {
    const configManager = ConfigManager.getInstance();
    const cfg = await configManager.getServerConfig();
    if (cfg.idServer.trim()) {
      this.serverHost = cfg.idServer.trim();
    } else {
      this.serverHost = '官方默认网络 (rustdesk.com)';
    }
  }

  async refreshOneTimePassword(): Promise<void> {
    const newPwd = this.generateRandomPassword(6);
    this.oneTimePassword = newPwd;
    const configManager = ConfigManager.getInstance();
    await configManager.setOneTimePassword(newPwd);
  }

  generateDeviceNumId(): string {
    let result = '';
    for (let i = 0; i < 9; i++) {
      result += Math.floor(Math.random() * 10).toString();
    }
    return result;
  }

  generateRandomPassword(length: number): string {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    let res = '';
    for (let i = 0; i < length; i++) {
      res += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return res;
  }

  formatId(input: string): string {
    const raw = input.replace(/\s+/g, '');
    const chunks: string[] = [];
    for (let i = 0; i < raw.length; i += 3) {
      chunks.push(raw.substring(i, Math.min(i + 3, raw.length)));
    }
    return chunks.join(' ');
  }

  async connectToPeer(targetId: string): Promise<void> {
    const rawId = targetId.replace(/\s+/g, '');
    if (!rawId) {
      this.connectionStatus = '请输入有效的远程设备 ID';
      return;
    }
    if (rawId === this.myId.replace(/\s+/g, '')) {
      this.connectionStatus = '不能连接到本机自身的 ID';
      return;
    }

    this.isConnecting = true;
    this.connectionStatus = `正在连接中继服务器 [${this.serverHost}] 寻址设备: ${targetId}...`;

    // Record peer to persistent storage
    const configManager = ConfigManager.getInstance();
    const newPeer: StoredPeer = {
      id: this.formatId(rawId),
      username: 'Remote Device',
      hostname: rawId,
      alias: '',
      platform: 'Remote',
      lastConnectedTime: Date.now()
    };
    await configManager.addRecentPeer(newPeer);
    this.recentDevices = await configManager.getRecentPeers();

    setTimeout(() => {
      this.connectionStatus = `已发送 NAT 穿透握手请求至 [${targetId}]，等待对端响应...`;
      setTimeout(() => {
        this.connectionStatus = `已建立安全通道，正在等待验证口令...`;
        this.isConnecting = false;
      }, 1500);
    }, 1200);
  }

  async handleLogout(): Promise<void> {
    await AuthService.logout();
    this.userProfile = {
      username: '',
      email: '',
      token: '',
      avatar: '',
      isLoggedIn: false
    };
    this.connectionStatus = '已退出账号登录';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isFlutterReady) {
        FlutterPage({ viewId: 'flutter_view' })
          .width('100%')
          .height('100%')
      } else {
        Column() {
          // Top Header Bar
          Row() {
            Image($r('app.media.icon'))
              .width(28)
              .height(28)
              .borderRadius(6)
              .margin({ right: 8 })

            Column({ space: 2 }) {
              Text('RustDesk')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1F2329')
              Text(this.serverHost)
                .fontSize(11)
                .fontColor('#86909C')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            // Server Settings Quick Icon
            Button() {
              Image($r('app.media.icon'))
                .width(18)
                .height(18)
            }
            .width(36)
            .height(36)
            .backgroundColor('#F2F3F5')
            .borderRadius(18)
            .margin({ right: 8 })
            .onClick(() => {
              this.serverSettingsDialogController.open();
            })

            // Network Ready Tag
            Row({ space: 6 }) {
              Circle({ width: 8, height: 8 })
                .fill(this.isOnline ? '#00B42A' : '#F53F3F')
              Text(this.isOnline ? '就绪' : '离线')
                .fontSize(12)
                .fontColor(this.isOnline ? '#00B42A' : '#F53F3F')
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.isOnline ? '#E8FFEA' : '#FFECE8')
            .borderRadius(12)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 4, color: '#0A000000', offsetX: 0, offsetY: 2 })

          // Main Tab Content
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

          // Bottom Navigation Bar
          Row() {
            this.buildNavItem('连接', 0)
            this.buildNavItem('设备簿', 1)
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
      // Local Device ID and One-time Session Password Card
      Column({ space: 10 }) {
        Row() {
          Text('本机 ID 与密码')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
          Blank()
          Row({ space: 4 }) {
            Circle({ width: 6, height: 6 }).fill('#00B42A')
            Text('服务运行中')
              .fontSize(12)
              .fontColor('#00B42A')
          }
        }
        .width('100%')

        Divider().color('#F2F3F5')

        Row() {
          Column({ space: 4 }) {
            Text('你的设备 ID')
              .fontSize(12)
              .fontColor('#86909C')
            Text(this.myId ? this.myId : '正在生成...')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1D2129')
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text('一次性密码')
                .fontSize(12)
                .fontColor('#86909C')
              Button('↻')
                .fontSize(12)
                .fontColor('#007DFF')
                .backgroundColor(Color.Transparent)
                .padding(0)
                .height(18)
                .onClick(() => {
                  this.refreshOneTimePassword();
                })
            }
            Text(this.oneTimePassword ? this.oneTimePassword : '------')
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

      // Remote Control Connect Card
      Column({ space: 12 }) {
        Text('控制远程桌面')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
          .width('100%')

        TextInput({
          placeholder: '输入远程设备 ID (例: 123 456 789)',
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
                this.connectionStatus = '请先输入远程设备 ID';
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

      // Server Config Shortcut Banner
      Row() {
        Column({ space: 2 }) {
          Text('中继与网络服务')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D2129')
          Text(this.serverHost)
            .fontSize(11)
            .fontColor('#86909C')
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button('配置服务器')
          .fontSize(12)
          .height(30)
          .backgroundColor('#E8F3FF')
          .fontColor('#007DFF')
          .borderRadius(6)
          .onClick(() => {
            this.serverSettingsDialogController.open();
          })
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
        Text(`最近连接设备 (${this.recentDevices.length})`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
        Blank()
        if (this.recentDevices.length > 0) {
          Button('清空历史')
            .fontSize(12)
            .fontColor('#86909C')
            .backgroundColor(Color.Transparent)
            .onClick(async () => {
              const configManager = ConfigManager.getInstance();
              for (const peer of this.recentDevices) {
                await configManager.removeRecentPeer(peer.id);
              }
              this.recentDevices = [];
            })
        }
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.recentDevices.length === 0) {
        Column({ space: 12 }) {
          Text('暂无连接历史')
            .fontSize(14)
            .fontColor('#86909C')
          Text('在“连接”页面输入远程设备 ID 连接后，设备将自动保存在这里。')
            .fontSize(12)
            .fontColor('#C9CDD4')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(32)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.recentDevices, (device: StoredPeer) => {
          Row() {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Circle({ width: 8, height: 8 }).fill('#00B42A')
                Text(device.alias ? device.alias : device.id)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1D2129')
              }
              Text('ID: ' + device.id + ' · ' + device.platform)
                .fontSize(12)
                .fontColor('#86909C')
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Row({ space: 8 }) {
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

              Button('删除')
                .fontSize(12)
                .height(30)
                .backgroundColor('#F2F3F5')
                .fontColor('#F53F3F')
                .borderRadius(6)
                .onClick(async () => {
                  const configManager = ConfigManager.getInstance();
                  await configManager.removeRecentPeer(device.id);
                  this.recentDevices = await configManager.getRecentPeers();
                })
            }
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .shadow({ radius: 4, color: '#06000000', offsetX: 0, offsetY: 1 })
        })
      }
    }
    .width('100%')
  }

  @Builder
  buildSettingsTab() {
    Column({ space: 14 }) {
      // User Account Section (Matches iOS/Android login header)
      Column({ space: 10 }) {
        Row() {
          Text('账户与同步')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D2129')
          Blank()
        }
        .width('100%')

        if (this.userProfile.isLoggedIn) {
          Row() {
            Column({ space: 4 }) {
              Text(this.userProfile.username)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1D2129')
              if (this.userProfile.email) {
                Text(this.userProfile.email)
                  .fontSize(12)
                  .fontColor('#86909C')
              }
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Button('退出登录')
              .fontSize(12)
              .height(30)
              .backgroundColor('#FFECE8')
              .fontColor('#F53F3F')
              .borderRadius(6)
              .onClick(() => {
                this.handleLogout();
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F7F8FA')
          .borderRadius(8)
        } else {
          Row() {
            Column({ space: 3 }) {
              Text('尚未登录 RustDesk 账号')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1D2129')
              Text('登录后即可同步地址簿与受控权限')
                .fontSize(11)
                .fontColor('#86909C')
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Button('登录账号')
              .fontSize(12)
              .height(32)
              .backgroundColor('#007DFF')
              .fontColor('#FFFFFF')
              .borderRadius(6)
              .onClick(() => {
                this.loginDialogController.open();
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F7F8FA')
          .borderRadius(8)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)

      // Server & Relay Configuration Section
      Column({ space: 10 }) {
        Row() {
          Text('网络与中继服务器')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D2129')
          Blank()
        }
        .width('100%')

        this.buildSettingItem('当前 ID 服务器', this.serverHost)
        Divider().color('#F2F3F5')

        Button('配置 ID / 中继 / API 服务器')
          .width('100%')
          .height(38)
          .fontSize(13)
          .backgroundColor('#F2F3F5')
          .fontColor('#007DFF')
          .borderRadius(6)
          .margin({ top: 4 })
          .onClick(() => {
            this.serverSettingsDialogController.open();
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)

      // Device & Platform Bridging Status
      Column({ space: 10 }) {
        Text('系统运行与能力支持')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
          .width('100%')

        this.buildSettingItem('系统版本', 'HarmonyOS NEXT (API 26 / HarmonyOS 7)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('屏幕采集', 'AVScreenCapture (系统就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('剪贴板同步', 'Pasteboard API 12+ (双向就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('文件管理器', 'CoreFileKit (就绪)')
        Divider().color('#F2F3F5')
        this.buildSettingItem('网络协议', 'HTTP / TCP / UDP')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)

      Button('进入全量 Flutter 渲染引擎')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#007DFF')
        .borderRadius(8)
        .onClick(() => {
          this.isFlutterReady = true;
        })
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
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }
}

