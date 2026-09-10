import { getConnectStatus, getLastRemoteId, peerGetSessionsCount } from '../platform/RustDeskBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RustDeskSession';

/**
 * Describe the value the core reports as its connection status.
 *
 * On this platform main_get_connect_status does not return a connection state machine. Its
 * ohos/android/ios arm returns hbb_common::config::get_online_state() -- the highest known
 * online state of the peers that have been queried -- with anything above zero collapsed to 1,
 * so the value is 0 (not established) or 1 (at least one queried peer is online). The wording
 * below says that, rather than inventing connect/probe/handshake phases the core does not
 * report here.
 */
function describeStatus(raw: string): string {
  if (!raw || raw.length === 0) {
    return '';
  }
  try {
    const parsed = JSON.parse(raw) as Record<string, number>;
    const num = parsed['status_num'];
    if (typeof num === 'number') {
      if (num <= 0) {
        return '未确认对端在线';
      }
      return '对端在线';
    }
  } catch (e) {
    // Not the shape we expect; show what the core actually said rather than hiding it.
  }
  return raw;
}

/**
 * Remote session view.
 *
 * This page used to load https://rustdesk.com/web/ into a WebView, with a fallback mode that
 * hand-drew a fake desktop on a canvas and logged the taps. Both looked like a session and
 * neither was one: the web client is a separate product that knows nothing about this app's
 * device id or its target, so choosing "connect" opened a web page rather than the peer.
 *
 * Streaming a real session needs the video path (the core's Rgba events into an XComponent
 * surface) and an event channel from the core to ArkTS, which is the P4 work in PLAN.md and
 * is not built yet. Until then this page states that plainly instead of substituting
 * something that resembles a session. It still shows what the core actually reports, so it is
 * usable for checking that the core is running and reachable.
 */

@Component
export struct RemoteSessionPage {
  @Prop targetId: string = '';
  onDisconnect?: () => void;

  @State private coreStatus: string = '';
  @State private lastRemoteId: string = '';
  @State private sessionCount: number = 0;
  @State private lastError: string = '';

  /** Polls the core while this page is up; cleared on disappear so it cannot outlive it. */
  private timerId: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timerId = setInterval(() => {
      this.refresh();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /**
   * Read the core's state.
   *
   * Guarded as a whole: a throw from the bridge aborts the whole interval tick, so the page
   * would silently freeze on stale values rather than reporting a problem. That is also the
   * shape of the crash this app had when the native module failed to load, and a status page
   * is not worth dying for.
   *
   * The core reports the connection status as JSON ({"status_num":N}), so it is parsed for
   * display rather than shown raw.
   */
  private refresh(): void {
    try {
      this.coreStatus = describeStatus(getConnectStatus());
      this.lastRemoteId = getLastRemoteId();
      this.sessionCount = peerGetSessionsCount(this.rawTarget(), 0);
      this.lastError = '';
    } catch (e) {
      this.lastError = '核心状态读取失败';
      hilog.warn(DOMAIN, TAG, 'core state unavailable: %{public}s', JSON.stringify(e));
    }
  }

  private rawTarget(): string {
    return this.targetId.replace(/\s+/g, '');
  }

  build() {
    Column({ space: 16 }) {
      this.buildHeader()
      this.buildStatusCard()
      this.buildPendingCard()
      Blank()
      this.buildFooter()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  private buildHeader() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text($r('app.string.session_target'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
        Text(this.targetId)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Button($r('app.string.session_disconnect'))
        .fontSize($r('app.float.font_caption'))
        .height(36)
        .backgroundColor($r('app.color.status_offline_bg'))
        .fontColor($r('app.color.danger'))
        .borderRadius($r('app.float.radius_control'))
        .onClick(() => {
          if (this.onDisconnect) {
            this.onDisconnect();
          }
        })
    }
    .width('100%')
  }

  @Builder
  private buildStatusCard() {
    Column({ space: 10 }) {
      if (this.lastError.length > 0) {
        Row() {
          Text(this.lastError)
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.danger'))
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.status_offline_bg'))
        .borderRadius($r('app.float.radius_control'))
      }

      Row() {
        Text($r('app.string.session_core_status'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.coreStatus.length > 0 ? this.coreStatus : $r('app.string.session_idle'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_body'))
      }
      .width('100%')

      Divider().color($r('app.color.divider'))

      Row() {
        Text($r('app.string.session_last_remote'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.lastRemoteId.length > 0 ? this.lastRemoteId : '—')
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_body'))
      }
      .width('100%')

      Divider().color($r('app.color.divider'))

      Row() {
        Text($r('app.string.session_peer_sessions'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.sessionCount.toString())
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_body'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
  }

  @Builder
  private buildPendingCard() {
    Column({ space: 8 }) {
      Text($r('app.string.session_pending_title'))
        .fontSize($r('app.float.font_subtitle'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.warning'))
        .width('100%')
      Text($r('app.string.session_pending_body'))
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
  }

  @Builder
  private buildFooter() {
    Row() {
      Button($r('app.string.common_close'))
        .layoutWeight(1)
        .height(44)
        .fontSize($r('app.float.font_body'))
        .backgroundColor($r('app.color.bg_subtle'))
        .fontColor($r('app.color.text_body'))
        .borderRadius($r('app.float.radius_control'))
        .onClick(() => {
          if (this.onDisconnect) {
            this.onDisconnect();
          }
        })
    }
    .width('100%')
  }
}
