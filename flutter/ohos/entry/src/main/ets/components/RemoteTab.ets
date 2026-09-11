/**
 * Remote tab: connect to a peer, and show this device's own ID and one-time password.
 *
 * The device ID comes from the Rust core through the Node-API bridge, so it is the real
 * value a peer must type. It previously came from a locally generated random number,
 * which connected to nothing.
 */

import { SectionCard } from './SectionCard';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getMyId, getTemporaryPassword, updateTemporaryPassword, LanPeer, getLanPeerList } from '../platform/RustDeskBridge';
import { ConfigManager, StoredPeer } from '../platform/ConfigStorage';

const DOMAIN = 0x0000;
const TAG = 'RustDeskRemote';

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
  @State private subTab: number = 0;
  @State private recentDevices: StoredPeer[] = [];

  /**
   * Peers the core has heard from on the local network.
   *
   * Refreshed on a timer while the LAN sub-tab is showing, because discovery is continuous in the
   * core: a peer that announces itself a second after the tab opens should appear without the
   * user having to leave and come back.
   */
  @State private lanPeers: LanPeer[] = [];
  private lanTimerId: number = -1;

  /**
   * Incremented by the page whenever the stored peer list changes.
   *
   * This tab loads once, in aboutToAppear, and a TabContent stays alive after it has been
   * shown, so without this the recent list would keep showing its first-build contents.
   */
  @Prop @Watch('onPeersChanged') peersRevision: number = 0;

  aboutToAppear(): void {
    this.loadDeviceIdentity();
    this.loadPeers();
    this.lanTimerId = setInterval(() => {
      // Only read while the list is on screen: the core keeps discovering either way, and
      // re-reading a list nobody is looking at is wasted work.
      if (this.subTab === 1) {
        this.loadLanPeers();
      }
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.lanTimerId !== -1) {
      clearInterval(this.lanTimerId);
      this.lanTimerId = -1;
    }
  }

  private loadLanPeers(): void {
    try {
      this.lanPeers = getLanPeerList();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not read LAN peers: %{public}s', JSON.stringify(e));
    }
  }

  onPeersChanged(): void {
    this.loadPeers();
  }

  /**
   * Read this device's identity from the core.
   *
   * The core reports an empty string before it has been initialised, which is a normal
   * "not ready yet" state rather than an error, so the UI shows a placeholder instead of
   * inventing a value.
   *
   * Guarded because this runs from aboutToAppear. A throwing bridge call here is what took the
   * app down when the native module failed to load -- the failure surfaced as a crash at this
   * exact line rather than as a missing id, so a blank id is the better outcome.
   *
   * The one-time password also comes from the core, which is what generates and rotates it.
   * It used to be read from a preferences key that nothing ever wrote, so the field could only
   * ever show its placeholder.
   */
  private loadDeviceIdentity(): void {
    try {
      this.myId = getMyId();
      this.oneTimePassword = getTemporaryPassword();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'device identity unavailable: %{public}s', JSON.stringify(e));
      this.myId = '';
      this.oneTimePassword = '';
    }
  }

  private loadPeers(): void {
    // Guarded like DevicesTab's identical call: this runs from aboutToAppear, and an
    // unhandled rejection on a startup path takes the process down.
    ConfigManager.getInstance().getRecentPeers().then((peers: StoredPeer[]) => {
      this.recentDevices = peers;
    }).catch((e: Object) => {
      hilog.warn(DOMAIN, TAG, 'could not load recent peers: %{public}s', JSON.stringify(e));
    });
  }

  /**
   * Validate the entered id and hand it to the page.
   *
   * The "connecting" line is shown only while this synchronous step is running, and the actual
   * outcome is unknown to this component, so the strip says what it knows: the request has been
   * passed on. It previously stayed on "正在连接…" forever after the first attempt -- including
   * after the password prompt was cancelled -- because nothing ever wrote it back.
   *
   * isConnecting was removed with it: it was set true and false in the same synchronous block,
   * so it could never be observed true and the button it gated never actually disabled.
   */
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
    this.connectionStatus = $r('app.string.session_request_sent');
    this.onConnect(this.remoteIdInput);
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
        // The raw digits are kept in state and formatting is applied only for display of the
        // local id and at submission. Reformatting on every keystroke -- which is what putting
        // formatId() in onChange did -- rewrites the field the user is typing into, moves the
        // caret to the end, and can disagree with the numeric input filter about the contents.
        // A dropped or transposed digit here means connecting to a different machine.
        TextInput({ placeholder: $r('app.string.home_id_placeholder'), text: this.remoteIdInput })
          .type(InputType.Number)
          .height(48)
          .fontSize(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_subtle'))
          .placeholderColor($r('app.color.text_hint'))
          .onChange((value: string) => {
            this.remoteIdInput = value.replace(/\s+/g, '');
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
            .enabled(this.remoteIdInput.length > 0)
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
            Row({ space: 6 }) {
              Text($r('app.string.home_one_time_password'))
                .fontSize($r('app.float.font_caption'))
                .fontColor($r('app.color.text_secondary'))
              // Rotating is a core operation; without this the password could only be read.
              Button($r('app.string.home_refresh'))
                .fontSize($r('app.float.font_caption'))
                .height(22)
                .padding({ left: 8, right: 8 })
                .backgroundColor($r('app.color.bg_subtle'))
                .fontColor($r('app.color.brand'))
                .borderRadius($r('app.float.radius_pill'))
                .onClick(() => {
                  this.rotateOneTimePassword();
                })
            }
            .alignItems(VerticalAlign.Center)

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

  /** Ask the core for a new one-time password and show it. */
  private rotateOneTimePassword(): void {
    try {
      updateTemporaryPassword();
      this.oneTimePassword = getTemporaryPassword();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not rotate the one-time password: %{public}s', JSON.stringify(e));
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
              // Read immediately rather than waiting for the timer, so switching to the tab shows
              // what the core already knows instead of an empty list for two seconds.
              this.loadLanPeers();
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
          // The LAN list belongs to the core, which discovers peers continuously; this only
          // re-reads what it has found, so an empty list means nothing has been heard yet rather
          // than that a scan is pending.
          if (this.lanPeers.length === 0) {
            this.buildEmptyState($r('app.string.peers_lan_scanning'), $r('app.string.peers_lan_hint'))
          } else {
            ForEach(this.lanPeers, (peer: LanPeer) => {
              this.buildLanPeerRow(peer)
            }, (peer: LanPeer) => peer.id)
          }
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

  /**
   * A peer found on the local network.
   *
   * The hostname is what distinguishes one entry from another here -- these peers have no alias,
   * and showing only the id would make two of them indistinguishable at a glance.
   */
  @Builder
  private buildLanPeerRow(peer: LanPeer) {
    HdsListItemCard({
      textItem: {
        primaryText: { text: peer.hostname.length > 0 ? peer.hostname : peer.id },
        secondaryText: { text: `${peer.id}  ${peer.platform}` }
      },
      onClick: () => {
        this.remoteIdInput = peer.id;
        this.onConnect(peer.id);
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
