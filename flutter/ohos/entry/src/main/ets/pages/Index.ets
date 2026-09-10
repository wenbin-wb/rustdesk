/**
 * Application shell.
 *
 * Adapts to the window rather than to a device category: the system `Tabs` component
 * carries the navigation in both layouts, switching its bar to the side once the window is
 * wide enough for a two-column arrangement. That covers phone portrait, phone landscape,
 * an unfolded foldable, a tablet and a 2in1 from one component -- there is no per-device
 * branch and no hand-drawn tab bar.
 *
 * See common/Breakpoint.ets for the thresholds and why they are width-based.
 */

import { HdsTabs, HdsTabsController, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { Breakpoint, observeBreakpoint, usesSideNavigation, pagePadding, maxContentWidth } from '../common/Breakpoint';
import { RemoteTab, formatId } from '../components/RemoteTab';
import { DevicesTab } from '../components/DevicesTab';
import { SettingsTab } from '../components/SettingsTab';
import { ServerSettingsDialog } from './ServerSettingsDialog';
import { LoginDialog } from './LoginDialog';
import { PasswordDialog } from './PasswordDialog';
import { RemoteSessionPage } from './RemoteSessionPage';
import { ConfigManager, ServerConfig, StoredPeer, UserProfile } from '../platform/ConfigStorage';
import { getOption } from '../platform/RustDeskBridge';
import { AuthService } from '../platform/AuthService';

@Entry
@Component
struct Index {
  @State private breakpoint: Breakpoint = Breakpoint.Sm;
  @State private serverLabel: ResourceStr = $r('app.string.home_public_relay');
  @State private userProfile: UserProfile = {
    username: '',
    email: '',
    token: '',
    avatar: '',
    isLoggedIn: false
  };
  @State private isInRemoteSession: boolean = false;
  @State private connectedTargetId: string = '';

  /** Detaches the breakpoint listeners; leaving them attached would keep this page alive. */
  private stopObservingBreakpoint: () => void = () => {};

  private tabsController: HdsTabsController = new HdsTabsController();

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
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.stopObservingBreakpoint = observeBreakpoint(this.getUIContext(), (bp: Breakpoint) => {
      this.breakpoint = bp;
    });
    this.loadServerConfig();
    this.loadUserProfile();
  }

  aboutToDisappear(): void {
    this.stopObservingBreakpoint();
  }

  private async loadServerConfig(): Promise<void> {
    const config = ConfigManager.getInstance();
    const cfg: ServerConfig = await config.getServerConfig();
    // Read the effective value back from the core rather than trusting the local copy, so
    // the label shows the server the app will actually use. An empty result means the core
    // is on its built-in default, i.e. the public servers.
    const fromCore = getOption('custom-rendezvous-server').trim();
    const effective = fromCore.length > 0 ? fromCore : cfg.idServer.trim();
    this.serverLabel = effective.length > 0
      ? effective
      : $r('app.string.home_public_relay');
  }

  private async loadUserProfile(): Promise<void> {
    const config = ConfigManager.getInstance();
    this.userProfile = await config.getUserProfile();
  }

  /** Route a connect request from either tab through the password step. */
  private beginConnect(targetId: string): void {
    this.connectedTargetId = targetId;
    const config = ConfigManager.getInstance();
    const rawId = targetId.replace(/\s+/g, '');
    const peer: StoredPeer = {
      id: formatId(rawId),
      username: '',
      hostname: rawId,
      alias: '',
      platform: '',
      lastConnectedTime: Date.now()
    };
    config.addRecentPeer(peer).then(() => {
      return config.getPeerPassword(rawId);
    }).then((saved: string) => {
      if (saved.length > 0) {
        // Already authorised for this peer, so go straight through.
        this.isInRemoteSession = true;
        return;
      }
      this.openPasswordDialog(targetId);
    });
  }

  private openPasswordDialog(targetId: string): void {
    const controller = new CustomDialogController({
      builder: PasswordDialog({
        targetId: targetId,
        onVerify: (password: string, remember: boolean) => {
          this.handlePasswordVerified(password, remember);
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true
    });
    controller.open();
  }

  private handlePasswordVerified(password: string, remember: boolean): void {
    const config = ConfigManager.getInstance();
    const rawId = this.connectedTargetId.replace(/\s+/g, '');
    const save = remember
      ? config.savePeerPassword(rawId, password)
      : config.removePeerPassword(rawId);
    save.then(() => {
      this.isInRemoteSession = true;
    });
  }

  private async handleLogout(): Promise<void> {
    await AuthService.logout();
    this.userProfile = { username: '', email: '', token: '', avatar: '', isLoggedIn: false };
  }

  build() {
    Stack() {
      if (this.isInRemoteSession) {
        RemoteSessionPage({
          targetId: this.connectedTargetId,
          onDisconnect: () => {
            this.isInRemoteSession = false;
          }
        })
          .width('100%')
          .height('100%')
      } else {
        this.buildShell()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  private buildShell() {
    Column() {
      this.buildHeader()
      this.buildTabs()
    }
    .width('100%')
    .height('100%')
    // The window is laid out full screen (see EntryAbility), so the page background runs
    // under the status bar and the gesture area -- that is what removes the window-coloured
    // strip at the top and bottom. The content itself is padded back out, below, since the
    // bars would otherwise sit on top of it.
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildHeader() {
    Row() {
      Image($r('app.media.icon'))
        .width(32)
        .height(32)
        .borderRadius(8)
        .margin({ right: 10 })

      Column({ space: 2 }) {
        Text($r('app.string.EntryAbility_label'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Text(this.serverLabel)
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Button($r('app.string.home_server'))
        .fontSize(13)
        .height(32)
        .backgroundColor($r('app.color.bg_subtle'))
        .fontColor($r('app.color.text_secondary'))
        .borderRadius(16)
        .onClick(() => {
          this.serverSettingsDialogController.open();
        })
    }
    .width('100%')
    .padding({ left: pagePadding(this.breakpoint), right: pagePadding(this.breakpoint), top: 12, bottom: 12 })
  }

  @Builder
  private buildTabs() {
    // HdsTabs from the UI Design Kit replaces the built-in Tabs. On the narrow breakpoint it
    // renders the bar as a floating pill -- inset from the sides and lifted off the bottom,
    // with the content visible behind and around it -- which is the HDS treatment for a
    // bottom bar and is what makes the page read as full screen rather than as a page with a
    // bar bolted underneath. On wide windows the same component is used vertically as a side
    // rail, where the floating treatment does not apply.
    HdsTabs({
      barPosition: usesSideNavigation(this.breakpoint) ? BarPosition.Start : BarPosition.End,
      controller: this.tabsController
    }) {
      TabContent() {
        this.buildScrollableTab(0)
      }
      .tabBar(new BottomTabBarStyle($r('app.media.tab_remote'), $r('app.string.tab_remote')))

      TabContent() {
        this.buildScrollableTab(1)
      }
      .tabBar(new BottomTabBarStyle($r('app.media.tab_devices'), $r('app.string.tab_devices')))

      TabContent() {
        this.buildScrollableTab(2)
      }
      .tabBar(new BottomTabBarStyle($r('app.media.tab_settings'), $r('app.string.tab_settings')))
    }
    .vertical(usesSideNavigation(this.breakpoint))
    .scrollable(false)
    .layoutWeight(1)
    .backgroundColor(Color.Transparent)
    .barFloatingStyle(usesSideNavigation(this.breakpoint) ? undefined : {
      barSideMargin: 16,
      barBottomMargin: 12
    } as HdsTabsFloatingStyle)
  }

  /**
   * A tab's body. Content is width-capped and centred so a wide 2in1 window does not
   * stretch text lines to the point of being hard to read.
   */
  @Builder
  private buildScrollableTab(index: number) {
    Scroll() {
      Column() {
        if (index === 0) {
          RemoteTab({
            serverLabel: this.serverLabel,
            onConnect: (targetId: string) => {
              this.beginConnect(targetId);
            },
            onTransferFile: () => {},
            onOpenServerSettings: () => {
              this.serverSettingsDialogController.open();
            }
          })
        } else if (index === 1) {
          DevicesTab({
            onConnect: (targetId: string) => {
              this.beginConnect(targetId);
            }
          })
        } else {
          SettingsTab({
            userProfile: this.userProfile,
            serverLabel: this.serverLabel,
            onLogin: () => {
              this.loginDialogController.open();
            },
            onLogout: () => {
              this.handleLogout();
            },
            onOpenServerSettings: () => {
              this.serverSettingsDialogController.open();
            }
          })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: maxContentWidth(this.breakpoint) })
      .padding({
        left: pagePadding(this.breakpoint),
        right: pagePadding(this.breakpoint),
        top: 12,
        bottom: 24
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
