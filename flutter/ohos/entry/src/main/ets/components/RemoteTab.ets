/**
 * Remote tab: connect to a peer, and show this device's own ID and one-time password.
 *
 * The device ID comes from the Rust core through the Node-API bridge, so it is the real
 * value a peer must type. It previously came from a locally generated random number,
 * which connected to nothing.
 */

import { SectionCard } from './SectionCard';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { getMyId, getCoreVersion } from '../platform/RustDeskBridge';
import { ConfigManager, StoredPeer } from '../platform/ConfigStorage';

/** Group digits in threes, the way the ID is written in the desktop clients. */
export function formatId(input: string): string {
  const raw = input.replace(/\s+/g, '');
  const chunks: string[] = [];
  for (let i = 0; i < raw.length; i += 3) {
    chunks.push(raw.substring(i, Math.min(i + 3, raw.length)));
  }
  return chunks.join(' ');
}

@Component
export struct RemoteTab {
  @Prop serverLabel: ResourceStr;
  /** Called when the user asks to connect to `targetId`. */
  onConnect: (targetId: string) => void = () => {};
  /** Called when the user asks to open a file transfer to `targetId`. */
  onTransferFile: (targetId: string) => void = () => {};
  /** Called to open the server settings dialog. */
  onOpenServerSettings: () => void = () => {};

  @State private remoteIdInput: string = '';
  @State private myId: string = '';
  @State private oneTimePassword: string = '';
  @State private connectionStatus: ResourceStr = $r('app.string.status_ready');
  @State private isConnecting: boolean = false;
  @State private subTab: number = 0;
  @State private recentDevices: StoredPeer[] = [];

  aboutToAppear(): void {
    this.loadDeviceIdentity();
    this.loadPeers();
  }

  /**
   * Read this device's ID from the core.
   *
   * The core reports an empty string before it has been initialised, which is a normal
   * "not ready yet" state rather than an error, so the UI shows a placeholder instead of
   * inventing a value.
   */
  private loadDeviceIdentity(): void {
    this.myId = getMyId();
    const config = ConfigManager.getInstance();
    config.getOneTimePassword().then((pwd: string) => {
      this.oneTimePassword = pwd;
    });
  }

  private loadPeers(): void {
    ConfigManager.getInstance().getRecentPeers().then((peers: StoredPeer[]) => {
      this.recentDevices = peers;
    });
  }

  private submit(): void {
    const raw = this.remoteIdInput.replace(/\s+/g, '');
    if (raw.length === 0) {
      this.connectionStatus = $r('app.string.error_invalid_id');
      return;
    }
    if (raw === this.myId.replace(/\s+/g, '')) {
      this.connectionStatus = $r('app.string.error_self_id');
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = $r('app.string.session_connecting');
    this.onConnect(this.remoteIdInput);
    this.isConnecting = false;
  }

  build() {
    Column({ space: 12 }) {
      this.buildConnectCard()
      this.buildThisDeviceCard()
      this.buildPeersCard()
    }
    .width('100%')
  }

  @Builder
  private buildConnectCard() {
    SectionCard({
      title: $r('app.string.home_connect_title'),
      trailing: this.serverLabel
    }) {
      Column({ space: 12 }) {
        TextInput({ placeholder: $r('app.string.home_id_placeholder'), text: this.remoteIdInput })
          .type(InputType.Number)
          .height(48)
          .fontSize(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_subtle'))
          .placeholderColor($r('app.color.text_hint'))
          .onChange((value: string) => {
            this.remoteIdInput = formatId(value);
          })
          .onSubmit(() => {
            this.submit();
          })

        Row({ space: 12 }) {
          Button($r('app.string.home_connect'))
            .layoutWeight(2)
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor($r('app.color.on_brand'))
            .borderRadius(12)
            .enabled(!this.isConnecting && this.remoteIdInput.length > 0)
            .onClick(() => {
              this.submit();
            })

          Button($r('app.string.home_transfer_file'))
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .backgroundColor($r('app.color.bg_subtle'))
            .fontColor($r('app.color.text_body'))
            .borderRadius(12)
            .enabled(this.remoteIdInput.length > 0)
            .onClick(() => {
              this.onTransferFile(this.remoteIdInput);
            })
        }
        .width('100%')

        Row() {
          Text(this.connectionStatus)
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.bg_subtle'))
        .borderRadius(8)
      }
      .width('100%')
    }
  }

  @Builder
  private buildThisDeviceCard() {
    SectionCard({
      title: $r('app.string.home_my_device_title'),
      trailing: $r('app.string.status_service_running'),
      statusColor: $r('app.color.status_online')
    }) {
      Column({ space: 12 }) {
        Divider().color($r('app.color.divider'))

        Row() {
          Column({ space: 4 }) {
            Text($r('app.string.home_my_id'))
              .fontSize($r('app.float.font_caption'))
              .fontColor($r('app.color.text_secondary'))
            Text(this.myId.length > 0 ? formatId(this.myId) : $r('app.string.home_id_generating'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Column({ space: 4 }) {
            Text($r('app.string.home_one_time_password'))
              .fontSize($r('app.float.font_caption'))
              .fontColor($r('app.color.text_secondary'))
            Text(this.oneTimePassword.length > 0 ? this.oneTimePassword : '------')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.brand'))
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildPeersCard() {
    SectionCard({ title: '' }) {
      Column({ space: 12 }) {
        Row({ space: 20 }) {
          Text($r('app.string.peers_recent'))
            .fontSize(15)
            .fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.subTab === 0 ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .onClick(() => {
              this.subTab = 0;
            })
          Text($r('app.string.peers_lan'))
            .fontSize(15)
            .fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.subTab === 1 ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .onClick(() => {
              this.subTab = 1;
            })
        }
        .width('100%')

        if (this.subTab === 0) {
          if (this.recentDevices.length === 0) {
            this.buildEmptyState($r('app.string.peers_recent_empty'), $r('app.string.peers_recent_empty_hint'))
          } else {
            ForEach(this.recentDevices, (device: StoredPeer) => {
              this.buildPeerRow(device)
            }, (device: StoredPeer) => device.id)
          }
        } else {
          this.buildEmptyState($r('app.string.peers_lan_scanning'), $r('app.string.peers_lan_hint'))
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildPeerRow(device: StoredPeer) {
    // The row itself is the connect action, as in the devices list, so a peer looks and
    // behaves the same wherever it appears.
    HdsListItemCard({
      textItem: {
        primaryText: { text: device.alias.length > 0 ? device.alias : device.id },
        secondaryText: { text: device.id }
      },
      onClick: () => {
        this.remoteIdInput = device.id;
        this.onConnect(device.id);
      }
    })
      .width('100%')
  }

  @Builder
  private buildEmptyState(primary: ResourceStr, hint: ResourceStr) {
    Column({ space: 6 }) {
      Text(primary)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text(hint)
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_hint'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}
