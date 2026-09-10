/**
 * Devices tab: the stored address book.
 *
 * Rows come from ConfigStorage, which is where the app records peers the user has connected
 * to. Each row is an HdsListItemCard so it matches the settings list, and the row's own tap is
 * the connect action -- there is no separate connect button, which is what made these rows a
 * different height and shape from every other list in the app.
 *
 * Deleting is the one destructive action, so it stays a distinct, labelled control rather than
 * being folded into the row tap.
 */

import { ConfigManager, StoredPeer } from '../platform/ConfigStorage';
import { HdsListItemCard } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RustDeskDevices';

@Component
export struct DevicesTab {
  @State private devices: StoredPeer[] = [];

  /**
   * Incremented by the page whenever the stored peer list changes.
   *
   * This tab loads once, in aboutToAppear, and a TabContent stays alive after it has been
   * shown, so without this the list would keep showing its first-build contents.
   */
  @Prop @Watch('onPeersChanged') peersRevision: number = 0;

  onConnect: (targetId: string) => void = () => {};

  /**
   * Tells the page the stored peer list changed, so it can refresh the other tab.
   *
   * This tab reloads itself after a delete, but the recent list on the remote tab is a second
   * view of the same store and has no way to know. Without this, a device deleted here stays
   * visible there.
   */
  onPeersMutated: () => void = () => {};

  aboutToAppear(): void {
    this.reload();
  }

  onPeersChanged(): void {
    this.reload();
  }

  private reload(): void {
    ConfigManager.getInstance().getRecentPeers().then((peers: StoredPeer[]) => {
      this.devices = peers;
    }).catch((e: Object) => {
      hilog.warn(DOMAIN, TAG, 'could not load stored peers: %{public}s', JSON.stringify(e));
    });
  }

  private remove(device: StoredPeer): void {
    const config = ConfigManager.getInstance();
    config.removeRecentPeer(device.id).then(() => {
      return config.removePeerPassword(device.id);
    }).then(() => {
      // Only notify: the parent bumps peersRevision, and this tab's own @Watch on it reloads.
      // Calling reload() here as well would read the store twice for no benefit.
      this.onPeersMutated();
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'could not remove the stored peer: %{public}s', JSON.stringify(e));
      this.onPeersMutated();
    });
  }

  private clearAll(): void {
    const config = ConfigManager.getInstance();
    // One write for the list itself, then the per-id password deletions. The passwords live on
    // distinct keys so doing them concurrently is safe; the peer list is a single key and must
    // not be written by several overlapping read-modify-write cycles.
    config.clearRecentPeers().then(() => {
      const work: Promise<void>[] = [];
      this.devices.forEach((device: StoredPeer) => {
        work.push(config.removePeerPassword(device.id));
      });
      return Promise.all(work);
    }).then(() => {
      // Only notify; this tab reloads through its own @Watch on peersRevision.
      this.onPeersMutated();
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'could not clear stored peers: %{public}s', JSON.stringify(e));
      this.onPeersMutated();
    });
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.devices_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Blank()
        if (this.devices.length > 0) {
          Button($r('app.string.devices_clear_all'))
            .fontSize($r('app.float.font_caption'))
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.danger'))
            .onClick(() => {
              this.clearAll();
            })
        }
      }
      .width('100%')

      if (this.devices.length === 0) {
        this.buildEmptyState()
      } else {
        ForEach(this.devices, (device: StoredPeer) => {
          this.buildDeviceRow(device)
        }, (device: StoredPeer) => device.id)
      }
    }
    .width('100%')
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 6 }) {
      Text($r('app.string.devices_empty'))
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.devices_empty_hint'))
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_hint'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
  }

  @Builder
  private buildDeviceRow(device: StoredPeer) {
    Column({ space: 2 }) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: device.alias.length > 0 ? device.alias : device.id },
          secondaryText: { text: device.id }
        },
        onClick: () => {
          this.onConnect(device.id);
        }
      })
        .width('100%')

      Row() {
        Blank()
        Button($r('app.string.devices_delete'))
          .fontSize($r('app.float.font_caption'))
          .height(28)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.danger'))
          .onClick(() => {
            this.remove(device);
          })
      }
      .width('100%')
      .padding({ right: 8, bottom: 4 })
    }
    .width('100%')
  }
}
