/**
 * Settings tab: account, server configuration, and system information.
 *
 * Every row is an HdsListItemCard from the UI Design Kit, and the section headings are plain
 * text rather than cards. The page previously wrapped hand-built cards -- containing hand-built
 * rows and buttons -- around HdsListItemCards, so it mixed two visual languages and stacked a
 * card inside a card. Rows that do something carry an onClick and say so in their secondary
 * line; there are no separate buttons, so every row has the same height, padding and press
 * feedback.
 *
 * The version rows read the linked artifacts rather than hardcoded strings, so a device
 * reports which core and which bridge it is actually running. That is the quickest way to
 * confirm the native module loaded, which is why these rows exist at all.
 */

import { UserProfile } from '../platform/ConfigStorage';
import { getCoreVersion, getBridgeVersion, getCoreBuildDate, getApiServer } from '../platform/RustDeskBridge';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RustDeskSettings';

@Component
export struct SettingsTab {
  @Prop userProfile: UserProfile;
  /** Shown for the current rendezvous/relay server. */
  @Prop serverLabel: ResourceStr;

  onLogin: () => void = () => {};
  onLogout: () => void = () => {};
  onOpenServerSettings: () => void = () => {};

  @State private coreVersion: string = '';
  @State private bridgeVersion: string = '';
  @State private buildDate: string = '';
  @State private apiServer: string = '';

  aboutToAppear(): void {
    // Guarded: these run before the first frame, and a throwing bridge call there takes the
    // process down instead of leaving a blank row.
    try {
      this.coreVersion = getCoreVersion();
      this.bridgeVersion = getBridgeVersion();
      this.buildDate = getCoreBuildDate();
      this.apiServer = getApiServer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'core versions unavailable: %{public}s', JSON.stringify(e));
    }
  }

  build() {
    Column({ space: 8 }) {
      this.sectionHeader($r('app.string.settings_account'))
      this.accountRow()

      this.sectionHeader($r('app.string.settings_server'))
      this.infoRow($r('app.string.settings_server_current'), this.serverLabel)
      if (this.apiServer.length > 0) {
        this.infoRow($r('app.string.dialog_server_api'), this.apiServer)
      }
      // The hint has to differ from the row above it. It used to repeat
      // settings_server_current, so "当前服务器" appeared twice in a row.
      this.actionRow($r('app.string.settings_server_configure'),
        $r('app.string.settings_server_configure_hint'),
        () => { this.onOpenServerSettings(); })

      this.sectionHeader($r('app.string.settings_system'))
      this.infoRow($r('app.string.settings_core_version'),
        this.coreVersion.length > 0 ? this.coreVersion : '—')
      this.infoRow($r('app.string.settings_bridge_version'),
        this.bridgeVersion.length > 0 ? this.bridgeVersion : '—')
      this.infoRow($r('app.string.settings_arch'), $r('app.string.settings_arch_value'))
      if (this.buildDate.length > 0) {
        this.infoRow($r('app.string.settings_build'), this.buildDate)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** A section label. Plain text: giving these card chrome would nest cards in cards. */
  @Builder
  private sectionHeader(title: ResourceStr) {
    Text(title)
      .fontSize($r('app.float.font_caption'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 8, bottom: 2 })
  }

  @Builder
  private infoRow(label: ResourceStr, value: ResourceStr) {
    HdsListItemCard({
      textItem: {
        primaryText: { text: label },
        secondaryText: { text: value }
      }
    })
      .width('100%')
  }

  /** A row that performs an action when tapped. */
  @Builder
  private actionRow(label: ResourceStr, hint: ResourceStr, action: () => void) {
    HdsListItemCard({
      textItem: {
        primaryText: { text: label },
        secondaryText: { text: hint }
      },
      onClick: () => {
        action();
      }
    })
      .width('100%')
  }

  @Builder
  private accountRow() {
    if (this.userProfile.isLoggedIn) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: this.userProfile.username },
          secondaryText: {
            text: this.userProfile.email.length > 0
              ? this.userProfile.email
              : $r('app.string.settings_logout')
          }
        },
        onClick: () => {
          this.onLogout();
        }
      })
        .width('100%')
    } else {
      HdsListItemCard({
        textItem: {
          primaryText: { text: $r('app.string.settings_account_none') },
          secondaryText: { text: $r('app.string.settings_account_hint') }
        },
        onClick: () => {
          this.onLogin();
        }
      })
        .width('100%')
    }
  }
}
