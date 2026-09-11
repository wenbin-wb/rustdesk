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
  /** Whether the pasteboard has been read once, so a push cannot send pre-existing content. */
  private seeded: boolean = false;

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
    // Seed from the current pasteboard before the first tick can run.
    //
    // Without this the first tick sees lastLocal as empty and pushes whatever was already on the
    // clipboard at the peer -- content the user copied before connecting, which is not something
    // they asked to send. The flag holds the push back until the seed lands, and is released even
    // when the read fails so a pasteboard problem cannot stop sync entirely.
    this.seeded = false;
    ClipboardBridge.getInstance().getText().then((text: string) => {
      this.lastLocal = text;
      this.seeded = true;
    }).catch((e: Object) => {
      hilog.warn(DOMAIN, TAG, 'could not read the pasteboard: %{public}s', JSON.stringify(e));
      // Treat whatever is there as already known, so sync proceeds without pushing it.
      this.lastLocal = '';
      this.seeded = true;
    });
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
    this.seeded = false;
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
   * The push is skipped on a tick that pulled. Both pasteboard calls are asynchronous and their
   * completions are not ordered, so a read issued after the write can still return the previous
   * local value -- which differs from both last values, and would then be sent to the peer,
   * overwriting what it just copied. Reading a tick later cannot see that stale value.
   *
   * Guarded as a whole so a pasteboard failure cannot kill the interval and leave sync silently
   * dead -- the failure mode where the feature looks enabled and does nothing.
   */
  private tick(): void {
    if (!this.running) {
      return;
    }
    let pulled = false;
    try {
      pulled = this.pullFromPeer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clipboard pull failed: %{public}s', JSON.stringify(e));
    }
    if (pulled) {
      return;
    }
    try {
      this.pushToPeer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clipboard push failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * Write whatever the peer has copied to this device's pasteboard.
   *
   * Reports whether anything was applied, so the caller can hold off pushing this tick.
   */
  private pullFromPeer(): boolean {
    const text = clipboardTakePending();
    if (text.length === 0) {
      return false;
    }
    // Remember it before writing, so the next push does not send it straight back.
    this.lastRemote = text;
    this.lastLocal = text;
    ClipboardBridge.getInstance().setText(text).then((ok: boolean) => {
      // Checked here as well as in pushToPeer: the write is asynchronous, so sync may have been
      // stopped between issuing it and its completion.
      if (!this.running) {
        return;
      }
      if (!ok) {
        hilog.warn(DOMAIN, TAG, 'could not write the peer clipboard to the pasteboard');
      }
    });
    return true;
  }

  /**
   * Send this device's copied text to the peer.
   *
   * The last value is compared before sending rather than after, because a pasteboard write and
   * the following read are not otherwise ordered.
   */
  private pushToPeer(): void {
    if (!this.seeded) {
      // The first read has not landed yet, so anything seen now would be pre-existing content.
      return;
    }
    ClipboardBridge.getInstance().getText().then((text: string) => {
      if (!this.running) {
        return;
      }
      if (text.length === 0) {
        return;
      }
      if (text === this.lastLocal) {
        // Unchanged since the last look. Note this also means copying the same text twice in a row
        // sends nothing the second time, even if the peer's clipboard has since changed -- the
        // pasteboard does not distinguish "same value, copied again" from "value never left", and
        // the peer's own clipboard is not something this end can see. Copying something else first
        // is the workaround; not worth tracking copy events to close, since the case is rare and
        // the consequence is a paste rather than data loss.
        return;
      }
      // A value that came from the peer is not new, so it is not sent back. Checked here as well
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
