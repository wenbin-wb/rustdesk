import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RustDeskClipboard';

export class ClipboardBridge {
  private static instance: ClipboardBridge | null = null;
  private onClipboardChangedCallback?: (text: string) => void;

  /**
   * Resolved lazily, not in a field initializer.
   *
   * A field initializer runs when getInstance() constructs this, which happens from
   * EntryAbility's own field initializer -- that is, during ability construction, before
   * onCreate and outside any try/catch. A throw there would fail the launch. Resolving on
   * first use keeps the failure inside the guarded methods below.
   */
  private sysPasteboard: pasteboard.SystemPasteboard | null = null;

  private constructor() {}

  public static getInstance(): ClipboardBridge {
    if (!ClipboardBridge.instance) {
      ClipboardBridge.instance = new ClipboardBridge();
    }
    return ClipboardBridge.instance;
  }

  private getPasteboard(): pasteboard.SystemPasteboard | null {
    if (!this.sysPasteboard) {
      try {
        this.sysPasteboard = pasteboard.getSystemPasteboard();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'clipboard unavailable: %{public}s', JSON.stringify(e));
        return null;
      }
    }
    return this.sysPasteboard;
  }

  public init(callback?: (text: string) => void): void {
    this.onClipboardChangedCallback = callback;
    const board = this.getPasteboard();
    if (!board) {
      return;
    }
    // Only subscribe when there is somewhere for the events to go. EntryAbility calls init()
    // with no callback, so registering regardless would leave a listener whose handler returns
    // immediately on every update -- dead weight that also hides the fact that nothing consumes
    // clipboard changes yet.
    if (!this.onClipboardChangedCallback) {
      return;
    }
    try {
      board.on('update', () => {
        this.notifyClipboardUpdate();
      });
    } catch {
      // Ignore listener error if system pasteboard service unavailable
    }
  }

  public async getText(): Promise<string> {
    const board = this.getPasteboard();
    if (!board) {
      return '';
    }
    try {
      const pasteData = await board.getData();
      if (pasteData && pasteData.getRecordCount() > 0) {
        return pasteData.getPrimaryText() ?? '';
      }
    } catch {
      return '';
    }
    return '';
  }

  public async setText(text: string): Promise<boolean> {
    const board = this.getPasteboard();
    if (!board) {
      return false;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(pasteData);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Deliver a clipboard change to the registered callback.
   *
   * The invocation is guarded: this runs from the system's update event, where a throw inside a
   * consumer's handler would become an unhandled rejection rather than something the consumer
   * can see.
   */
  private async notifyClipboardUpdate(): Promise<void> {
    const callback = this.onClipboardChangedCallback;
    if (!callback) {
      return;
    }
    try {
      const text = await this.getText();
      callback(text);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clipboard change handler failed: %{public}s', JSON.stringify(e));
    }
  }
}
