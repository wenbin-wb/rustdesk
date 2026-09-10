/**
 * Settings tab: account, server configuration, and system information.
 *
 * The version rows read the linked artifacts rather than a hardcoded string, so a device
 * visibly reports which core and which bridge it is actually running. That is the quickest
 * way to confirm the native module loaded, and it is why these two rows exist at all.
 */

import { SectionCard } from './SectionCard';
import { UserProfile } from '../platform/ConfigStorage';
import { getCoreVersion, getBridgeVersion, getCoreBuildDate, getApiServer } from '../platform/RustDeskBridge';

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
    this.coreVersion = getCoreVersion();
    this.bridgeVersion = getBridgeVersion();
    this.buildDate = getCoreBuildDate();
    this.apiServer = getApiServer();
  }

  build() {
    Column({ space: 12 }) {
      this.buildAccountCard()
      this.buildServerCard()
      this.buildSystemCard()
    }
    .width('100%')
  }

  @Builder
  private buildAccountCard() {
    SectionCard({ title: $r('app.string.settings_account') }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.userProfile.isLoggedIn
            ? this.userProfile.username
            : $r('app.string.settings_account_none'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_title'))
          Text(this.userProfile.isLoggedIn && this.userProfile.email.length > 0
            ? this.userProfile.email
            : $r('app.string.settings_account_hint'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        if (this.userProfile.isLoggedIn) {
          Button($r('app.string.settings_logout'))
            .fontSize(13)
            .height(32)
            .backgroundColor($r('app.color.status_offline_bg'))
            .fontColor($r('app.color.danger'))
            .borderRadius(8)
            .onClick(() => {
              this.onLogout();
            })
        } else {
          Button($r('app.string.settings_login'))
            .fontSize(13)
            .height(32)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_brand'))
            .borderRadius(8)
            .onClick(() => {
              this.onLogin();
            })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildServerCard() {
    SectionCard({ title: $r('app.string.settings_server') }) {
      Column({ space: 12 }) {
        this.buildInfoRow($r('app.string.settings_server_current'), this.serverLabel)
        if (this.apiServer.length > 0) {
          this.buildInfoRow($r('app.string.dialog_server_api'), this.apiServer)
        }
        Divider().color($r('app.color.divider'))
        Button($r('app.string.settings_server_configure'))
          .width('100%')
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.bg_subtle'))
          .fontColor($r('app.color.brand'))
          .borderRadius(10)
          .onClick(() => {
            this.onOpenServerSettings();
          })
      }
      .width('100%')
    }
  }

  @Builder
  private buildSystemCard() {
    SectionCard({ title: $r('app.string.settings_system') }) {
      Column({ space: 12 }) {
        this.buildInfoRow($r('app.string.settings_core_version'),
          this.coreVersion.length > 0 ? this.coreVersion : '—')
        Divider().color($r('app.color.divider'))
        this.buildInfoRow($r('app.string.settings_bridge_version'),
          this.bridgeVersion.length > 0 ? this.bridgeVersion : '—')
        Divider().color($r('app.color.divider'))
        this.buildInfoRow($r('app.string.settings_arch'), $r('app.string.settings_arch_value'))
        if (this.buildDate.length > 0) {
          Divider().color($r('app.color.divider'))
          this.buildInfoRow('Build', this.buildDate)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildInfoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_body'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }
}
