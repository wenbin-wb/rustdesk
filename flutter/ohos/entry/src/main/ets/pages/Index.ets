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

import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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

const DOMAIN = 0x0000;
const TAG = 'RustDesk';

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
  /**
   * Bumped whenever the stored peer list changes.
   *
   * The tabs load their lists in aboutToAppear, which runs once: Tabs keeps a TabContent alive
   * after it has been shown, so returning to a tab does not rebuild it. Connecting to a new
   * peer therefore left both lists showing their contents as of first build. The tabs watch
   * this value and reload when it changes.
   */
  @State private peersRevision: number = 0;

  @State private isInRemoteSession: boolean = false;
  @State private connectedTargetId: string = '';

  /**
   * Server configuration, owned here and linked into the settings dialog.
   *
   * The dialog used to read this itself on aboutToAppear, which ran once -- when the page was
   * built, before the core and preferences were ready -- so reopening it showed empty fields
   * even after a successful save. Owning it here and refreshing before each open makes what
   * the dialog shows the same thing the app actually uses.
   */
  @State private serverCfg: ServerConfig = {
    idServer: '',
    relayServer: '',
    apiServer: '',
    key: '',
    webClientUrl: ''
  };

  /** Detaches the breakpoint listeners; leaving them attached would keep this page alive. */
  private stopObservingBreakpoint: () => void = () => {};

  private tabsController: HdsTabsController = new HdsTabsController();

  // Published by EntryAbility from the window's avoid areas, in px. The window is laid out
  // full screen, so the framework does not inset content on its own and these have to be
  // applied here. Measured on device: without them the tab bar sat on the last pixel row.
  @StorageProp('statusBarInsetPx') statusBarInsetPx: number = 0;
  @StorageProp('navIndicatorInsetPx') navIndicatorInsetPx: number = 0;

  // customStyle: true on every dialog. Without it the framework wraps the content in its own
  // opaque, rounded container, which shows around the edges of our narrower card -- the white
  // rim. With it the builder's own background and radius are the only ones drawn.
  private serverSettingsDialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog({
      serverCfg: $serverCfg,
      onSaved: () => {
        this.loadServerConfig();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true,
    maskColor: $r('app.color.mask')
  });

  private loginDialogController: CustomDialogController = new CustomDialogController({
    builder: LoginDialog({
      onLoginSuccess: (profile: UserProfile) => {
        this.userProfile = profile;
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true,
    maskColor: $r('app.color.mask')
  });

  // Target of the password dialog. The dialog needs it at open time, so it is state on the
  // page rather than a constructor argument.
  @State private passwordTargetId: string = '';

  /**
   * Held as a member, not as a local.
   *
   * This dialog used to be built into a local `const controller` inside the open method. The
   * dialog opened, but its own `controller` member was never bound, so the first call to
   * `this.controller.close()` -- on tapping connect -- threw
   * "Cannot read property close of undefined" and took the app down. The framework binds the
   * controller through this declaration, so the reference has to outlive the open call.
   */
  private passwordDialogController: CustomDialogController = new CustomDialogController({
    builder: PasswordDialog({
      targetId: $passwordTargetId,
      onVerify: (password: string, remember: boolean) => {
        this.handlePasswordVerified(password, remember);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true,
    maskColor: $r('app.color.mask')
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
    // Keep the full configuration, not just the label: the settings dialog edits these values
    // and shows them when reopened.
    this.serverCfg = cfg;
    // Read the effective value back from the core rather than trusting the local copy, so
    // the label shows the server the app will actually use. An empty result means the core
    // is on its built-in default, i.e. the public servers.
    const fromCore = getOption('custom-rendezvous-server').trim();
    const effective = fromCore.length > 0 ? fromCore : cfg.idServer.trim();
    this.serverLabel = effective.length > 0
      ? effective
      : $r('app.string.home_public_relay');
  }

  /**
   * Show the server settings, with the stored values loaded first.
   *
   * The load is awaited on purpose: opening straight away would show whatever the page last
   * held, and on a cold start that is empty. A failed load must not stop the dialog from
   * opening, or a bad read would make the settings unreachable; the fields would simply open
   * with the values the page already had.
   */
  private async openServerSettings(): Promise<void> {
    try {
      await this.loadServerConfig();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not load the server configuration: %{public}s', JSON.stringify(e));
    }
    this.serverSettingsDialogController.open();
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
      // Both peer lists load once when their tab is first built and a TabContent is kept alive
      // after that, so tell them to reload or the peer just connected to will not appear.
      this.peersRevision++;
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
    this.passwordTargetId = targetId;
    this.passwordDialogController.open();
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
      // Background layer. This is the only thing that bleeds under the status bar and the
      // gesture indicator, which is what removes the window-coloured strip at the top and
      // bottom. Everything else is a sibling that does NOT expand, so the system insets it
      // into the safe area automatically -- expandSafeArea applies per component, and that
      // is the whole mechanism. No avoid-area arithmetic is needed.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_page'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

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
  }

  @Builder
  private buildShell() {
    Column() {
      this.buildHeader()
      this.buildTabs()
    }
    .width('100%')
    .height('100%')
    // Inset the content clear of the status bar and the gesture bar, which the full-screen
    // window no longer does for us. The background layer underneath still bleeds, so the page
    // reads as full screen while nothing sits under a system bar.
    .padding({
      top: px2vp(this.statusBarInsetPx),
      bottom: px2vp(this.navIndicatorInsetPx)
    })
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
           this.openServerSettings();
        })
    }
    .width('100%')
    .padding({ left: pagePadding(this.breakpoint), right: pagePadding(this.breakpoint), top: 12, bottom: 12 })
  }

  @Builder
  private buildTabs() {
    // HdsTabs from the UI Design Kit, replacing the built-in Tabs.
    //
    // barOverlap(true) is what makes the bar float rather than occupy layout space, and
    // barBottomMargin must be non-zero for the lift to show. Without barOverlap the bar keeps
    // full width and reserves its own row -- measured on device as items spanning the whole
    // 0..1276 with the bar flush at the screen edge, which is exactly "not floating".
    //
    // On the wide breakpoint the same component is used as a vertical side rail, where
    // overlap is off because a rail sits beside the content rather than over it.
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
    .width('100%')
    .layoutWeight(1)
    .barHeight(65)
    .barOverlap(!usesSideNavigation(this.breakpoint))
    .vertical(usesSideNavigation(this.breakpoint))
    .scrollable(false)
    .backgroundColor(Color.Transparent)
    .barFloatingStyle({
      // Explicit widths per band, otherwise the pill keeps the full width once the style
      // engages and only the margins move.
      barWidth: { smallWidth: 260, mediumWidth: 320, largeWidth: 420 },
      barBottomMargin: 20,
      // A tinted gradient under the bar so content fades out behind it instead of being cut
      // off at a hard edge.
      gradientMask: { maskColor: '#66F1F3F5', maskHeight: 72 },
      // The frosted material. IMMERSIVE is the translucent variant and ADAPTIVE follows the
      // system theme, so dark mode needs no branch here.
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
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
            peersRevision: this.peersRevision,
            onConnect: (targetId: string) => {
              this.beginConnect(targetId);
            },
            onTransferFile: () => {},
            onOpenServerSettings: () => {
               this.openServerSettings();
            }
          })
        } else if (index === 1) {
          DevicesTab({
            peersRevision: this.peersRevision,
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
               this.openServerSettings();
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
        // The bar floats over the content (barOverlap), so the content has to leave room for
        // it: the bar is 65vp tall with a 20vp lift, plus room to scroll past comfortably.
        bottom: usesSideNavigation(this.breakpoint) ? 24 : 104
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
