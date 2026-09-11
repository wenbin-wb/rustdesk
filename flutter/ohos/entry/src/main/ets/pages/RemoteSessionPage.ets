import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoSurface } from '../components/VideoSurface';
import { ClipboardSync } from '../platform/ClipboardSync';
import {
  sessionAdd, sessionStart, sessionClose, pollUiEvents,
  getConnectStatus, getLastRemoteId, peerGetSessionsCount
} from '../platform/RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskSession';

/** How often the core's queued status events are drained. */
const EVENT_POLL_MS = 200;

/**
 * A remote session: the peer's desktop, with a status strip over it.
 *
 * The page owns the session's life. It registers the session with the core, starts the
 * connection, and tears both down on the way out. The picture is drawn by the core straight into
 * the surface -- see components/VideoSurface.ets and flutter/ohos/native/src/surface.rs -- so
 * nothing on this page is per-frame.
 */
@Component
export struct RemoteSessionPage {
  @Prop targetId: string = '';
  /** The password the user entered, already checked against the peer by the core. */
  @Prop password: string = '';
  /** True when the password is the peer's one-time password rather than its permanent one. */
  @Prop passwordIsShared: boolean = false;
  onDisconnect?: () => void;

  /**
   * Identifies this session to the core. Generated here and kept for the session's life, because
   * every later call -- close, video -- is keyed on it.
   */
  @State private sessionId: string = '';
  @State private status: string = '';
  @State private errorMessage: string = '';
  @State private remoteId: string = '';
  @State private peerSessions: number = 0;
  @State private started: boolean = false;

  private timerId: number = -1;
  /** Guards against starting twice, which would leave a second connection behind. */
  private startAttempted: boolean = false;

  aboutToAppear(): void {
    this.sessionId = this.newSessionId();
    this.beginSession();
    this.timerId = setInterval(() => {
      this.poll();
    }, EVENT_POLL_MS);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    // Stop clipboard sync before closing the session: it pushes at whatever sessions exist, so
    // leaving it running would have it keep pushing this device's copies at a peer that is gone.
    ClipboardSync.getInstance().stop();
    // Release in the same order the session was built: stop the picture, then the session, then
    // forget the id so a later connect on the same peer starts clean.
    if (this.sessionId.length > 0) {
      sessionClose(this.sessionId);
      this.sessionId = '';
    }
  }

  /**
   * A v4 UUID, which is what the core's SessionID is.
   *
   * Built here rather than pulled from the core because the id has to exist before the session is
   * registered. `crypto.randomUUID` is not available in ArkTS, so this follows the v4 layout with
   * the platform's random source.
   */
  private newSessionId(): string {
    const bytes = new Uint8Array(16);
    for (let i = 0; i < 16; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    // Version 4, variant 1, as the UUID specification requires.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex: string[] = [];
    for (let i = 0; i < 16; i++) {
      hex.push((bytes[i] < 16 ? '0' : '') + bytes[i].toString(16));
    }
    const h = hex.join('');
    return `${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}`;
  }

  /**
   * Register and start the connection.
   *
   * Guarded as a whole: this runs from aboutToAppear, where a throw takes the process down, and
   * the core reports failures as return values rather than exceptions in any case.
   */
  private beginSession(): void {
    if (this.startAttempted) {
      return;
    }
    this.startAttempted = true;
    try {
      const addErr = sessionAdd(this.sessionId, this.rawTarget(), this.password, this.passwordIsShared);
      if (addErr.length > 0) {
        this.fail(`无法创建会话：${addErr}`);
        return;
      }
      const startErr = sessionStart(this.sessionId, this.rawTarget());
      if (startErr.length > 0) {
        this.fail(`无法发起连接：${startErr}`);
        return;
      }
      this.started = true;
      this.status = '正在连接…';
      // Clipboard sync follows the session's life: it needs a session to send to, and a sync
      // running without one would silently do nothing.
      ClipboardSync.getInstance().start();
      hilog.info(DOMAIN, TAG, 'session %{public}s started', this.sessionId);
    } catch (e) {
      this.fail(`连接失败：${JSON.stringify(e)}`);
    }
  }

  private fail(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
    this.errorMessage = message;
  }

  private rawTarget(): string {
    return this.targetId.replace(/\s+/g, '');
  }

  /**
   * Read the core's state and drain its queued events.
   *
   * Guarded as a whole: a throw here would abort the whole tick and freeze the strip on stale
   * values rather than reporting the problem.
   */
  private poll(): void {
    try {
      const events = pollUiEvents();
      for (const e of events) {
        if (e === 'close') {
          this.status = '连接已关闭';
        } else if (e.startsWith('rgba:')) {
          // A frame is on its way into the surface; the strip just reports that it arrived.
          this.status = '已连接';
        } else if (e.length > 0) {
          this.status = e;
        }
      }
      this.remoteId = getLastRemoteId();
      this.peerSessions = peerGetSessionsCount(this.rawTarget(), 0);
        if (this.rawTarget().length > 0) {
          const raw = getConnectStatus();
          if (raw.length > 0 && this.status.length === 0) {
            this.status = raw;
          }
        }
    } catch (e) {
      this.errorMessage = '核心状态读取失败';
      hilog.warn(DOMAIN, TAG, 'core state unavailable: %{public}s', JSON.stringify(e));
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // The surface fills the page; the strip floats over it.
      VideoSurface({
        sessionId: this.started ? this.sessionId : '',
        display: 0,
        onError: (message: string) => {
          this.errorMessage = message;
        }
      })
        .width('100%')
        .height('100%')

      this.buildStrip()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  @Builder
  private buildStrip() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.started ? $r('app.color.status_online') : $r('app.color.status_offline'))

        Text(this.remoteId.length > 0 ? this.remoteId : this.targetId)
          .fontSize($r('app.float.font_caption'))
          .fontColor(Color.White)

        Blank()

        Button($r('app.string.session_disconnect'))
          .fontSize($r('app.float.font_caption'))
          .height(28)
          .backgroundColor($r('app.color.status_offline_bg'))
          .fontColor(Color.White)
          .borderRadius($r('app.float.radius_control'))
          .onClick(() => {
            if (this.onDisconnect) {
              this.onDisconnect();
            }
          })
      }
      .width('100%')

      if (this.errorMessage.length > 0 || this.status.length > 0) {
        Text(this.errorMessage.length > 0 ? this.errorMessage : this.status)
          .fontSize($r('app.float.font_caption'))
          .fontColor(this.errorMessage.length > 0 ? $r('app.color.warning') : Color.White)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('94%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor('rgba(29, 33, 41, 0.85)')
    .borderRadius($r('app.float.radius_card'))
    .margin({ top: 12 })
  }
}
