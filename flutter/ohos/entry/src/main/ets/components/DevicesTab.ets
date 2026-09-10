/**
 * Devices tab: the stored address book.
 *
 * Rows come from ConfigStorage, which is where the app records peers the user has
 * connected to. Connect and delete both report back to the shell so it owns navigation.
 */

import { SectionCard } from './SectionCard';
import { ConfigManager, StoredPeer } from '../platform/ConfigStorage';

@Component
export struct DevicesTab {
  @State private devices: StoredPeer[] = [];

  onConnect: (targetId: string) => void = () => {};

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    ConfigManager.getInstance().getRecentPeers().then((peers: StoredPeer[]) => {
      this.devices = peers;
    });
  }

  private remove(device: StoredPeer): void {
    const config = ConfigManager.getInstance();
    config.removeRecentPeer(device.id).then(() => {
      return config.removePeerPassword(device.id);
    }).then(() => {
      this.reload();
    });
  }

  private clearAll(): void {
    const config = ConfigManager.getInstance();
    const work: Promise<void>[] = [];
    this.devices.forEach((device: StoredPeer) => {
      work.push(config.removeRecentPeer(device.id));
      work.push(config.removePeerPassword(device.id));
    });
    Promise.all(work).then(() => {
      this.reload();
    });
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.devices_title'))
          .fontSize($r('app.float.font_headline'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Blank()
        if (this.devices.length > 0) {
          Button($r('app.string.devices_clear_all'))
            .fontSize(14)
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
        SectionCard({ title: '' }) {
          Column({ space: 6 }) {
            Text($r('app.string.devices_empty'))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
            Text($r('app.string.devices_empty_hint'))
              .fontSize($r('app.float.font_caption'))
              .fontColor($r('app.color.text_hint'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 32, bottom: 32 })
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        ForEach(this.devices, (device: StoredPeer) => {
          SectionCard({ title: '' }) {
            Row() {
              Column({ space: 4 }) {
                Text(device.alias.length > 0 ? device.alias : device.id)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_title'))
                Text(device.id)
                  .fontSize($r('app.float.font_caption'))
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Row({ space: 8 }) {
                Button($r('app.string.devices_connect'))
                  .fontSize(13)
                  .height(32)
                  .backgroundColor($r('app.color.brand'))
                  .fontColor($r('app.color.on_brand'))
                  .borderRadius(8)
                  .onClick(() => {
                    this.onConnect(device.id);
                  })

                Button($r('app.string.devices_delete'))
                  .fontSize(13)
                  .height(32)
                  .backgroundColor($r('app.color.bg_subtle'))
                  .fontColor($r('app.color.danger'))
                  .borderRadius(8)
                  .onClick(() => {
                    this.remove(device);
                  })
              }
            }
            .width('100%')
          }
        }, (device: StoredPeer) => device.id)
      }
    }
    .width('100%')
  }
}
