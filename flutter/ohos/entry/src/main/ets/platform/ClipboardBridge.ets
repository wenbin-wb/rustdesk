import { pasteboard } from '@kit.BasicServicesKit';
import { MethodChannel } from '@ohos/flutter_ohos';

export class ClipboardBridge {
  private static instance: ClipboardBridge | null = null;
  private channel: MethodChannel | null = null;
  private sysPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();

  private constructor() {}

  public static getInstance(): ClipboardBridge {
    if (!ClipboardBridge.instance) {
      ClipboardBridge.instance = new ClipboardBridge();
    }
    return ClipboardBridge.instance;
  }

  public init(channel: MethodChannel): void {
    this.channel = channel;
    this.sysPasteboard.on('update', () => {
      this.notifyClipboardUpdate();
    });
  }

  public async getText(): Promise<string> {
    try {
      const pasteData = await this.sysPasteboard.getData();
      if (pasteData && pasteData.getRecordCount() > 0) {
        return pasteData.getPrimaryText() ?? '';
      }
    } catch {
      return '';
    }
    return '';
  }

  public async setText(text: string): Promise<boolean> {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await this.sysPasteboard.setData(pasteData);
      return true;
    } catch {
      return false;
    }
  }

  private async notifyClipboardUpdate(): Promise<void> {
    if (!this.channel) {
      return;
    }
    const text = await this.getText();
    this.channel.invokeMethod('onClipboardChanged', text);
  }
}
