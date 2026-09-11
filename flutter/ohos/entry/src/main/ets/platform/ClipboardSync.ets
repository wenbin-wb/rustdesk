import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClipboardBridge } from './ClipboardBridge';
import { clipboardTakePending, clipboardSend } from './RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskClipSync';

/**
 * How often the peer's clipboard is checked for and this device's is offered.
 *
 * Polling rather than push in both directions, for the same reason the rest of this bridge is:
 * HarmonyOS reads the pasteboard from ArkTS and the core has no way to call into it, so the only
 * direction the core can initiate is the one where ArkTS asks.
 *
 * 500ms is well under the interval at which a person copies something new, and cheap: one
 * preference-free pasteboard read plus one lock on the core side per tick.
 */
const POLL_INTERVAL_MS = 500;

/**
 * Keeps the local pasteboard and the peer's clipboard in step.
 *
 * Lives for as long as a session does, and is stopped when there is none: a clipboard sync that
 * outlived its session would push this device's copies at a peer that is no longer connected.
 *
 * ### Echo suppression
 *
 * Both directions carry a "last value" so a clipboard that arrived from the peer is not
 * immediately sent back. Without that the two ends copy the same text to each other forever --
 * each seeing a change the other just made. The values are compared before sending, not after,
 * because the pasteboard write and the next read are not ordered otherwise.
 */
export class ClipboardSync {
  private static instance: ClipboardSync | null = null;
  private timerId: number = -1;
  /** The last text seen on the local pasteboard, so an unchanged one is not re-sent. */
  private lastLocal: string = '';
  /** The last text applied from the peer, so it is not echoed straight back. */
  private lastRemote: string = '';
  private running: boolean = false;

  private constructor() {}

  public static getInstance(): ClipboardSync {
    if (!ClipboardSync.instance) {
      ClipboardSync.instance = new ClipboardSync();
    }
    return ClipboardSync.instance;
  }

  /** Start syncing. Idempotent: a second call while running does nothing. */
  public start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    // Seed from the current pasteboard so the first tick does not report the existing content as
    // a new copy and push it at the peer.
    ClipboardBridge.getInstance().getText().then((text: string) => {
      if (this.lastLocal.length === 0) {
        this.lastLocal = text;
      }
    }).catch(() => {});
    this.timerId = setInterval(() => {
      this.tick();
    }, POLL_INTERVAL_MS);
    hilog.info(DOMAIN, TAG, 'clipboard sync started');
  }

  /** Stop syncing. Safe to call when not running. */
  public stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.running = false;
    this.lastLocal = '';
    this.lastRemote = '';
    hilog.info(DOMAIN, TAG, 'clipboard sync stopped');
  }

  public isRunning(): boolean {
    return this.running;
  }

  /**
   * One round: apply anything the peer sent, then offer anything new locally.
   *
   * Guarded as a whole so a pasteboard failure cannot kill the interval and leave sync silently
   * dead -- the failure mode where the feature looks enabled and does nothing.
   */
  private tick(): void {
    if (!this.running) {
      return;
    }
    try {
      this.pullFromPeer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clipboard pull failed: %{public}s', JSON.stringify(e));
    }
    try {
      this.pushToPeer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clipboard push failed: %{public}s', JSON.stringify(e));
    }
  }

  /** Write whatever the peer has copied to this device's pasteboard. */
  private pullFromPeer(): void {
    const text = clipboardTakePending();
    if (text.length === 0) {
      return;
    }
    // Remember it before writing, so the next push does not send it straight back.
    this.lastRemote = text;
    this.lastLocal = text;
    ClipboardBridge.getInstance().setText(text).then((ok: boolean) => {
      if (!ok) {
        hilog.warn(DOMAIN, TAG, 'could not write the peer clipboard to the pasteboard');
      }
    });
  }

  /** Send this device's copied text to the peer. */
  private pushToPeer(): void {
    ClipboardBridge.getInstance().getText().then((text: string) => {
      if (!this.running) {
        return;
      }
      if (text.length === 0 || text === this.lastLocal) {
        return;
      }
      // A value that came from the peer is not new, so it is not sent back. Compared here as well
      // as in pullFromPeer because the pasteboard may normalise what was written to it.
      if (text === this.lastRemote) {
        this.lastLocal = text;
        return;
      }
      this.lastLocal = text;
      const err = clipboardSend(text);
      if (err.length > 0) {
        // No session is the ordinary case while connecting, so this is not reported as a fault.
        hilog.debug(DOMAIN, TAG, 'clipboard not sent: %{public}s', err);
      }
    });
  }
}
