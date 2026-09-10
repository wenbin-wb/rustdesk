import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult, MethodCallHandler } from '@ohos/flutter_ohos';
import { ClipboardBridge } from '../platform/ClipboardBridge';
import { FilePickerBridge } from '../platform/FilePickerBridge';
import { ScreenCaptureBridge } from '../platform/ScreenCaptureBridge';

class RustDeskMethodHandler implements MethodCallHandler {
  private clipboardBridge: ClipboardBridge;
  private filePickerBridge: FilePickerBridge | null;
  private screenCaptureBridge: ScreenCaptureBridge | null;

  constructor(
    clipboard: ClipboardBridge,
    filePicker: FilePickerBridge | null,
    screenCapture: ScreenCaptureBridge | null
  ) {
    this.clipboardBridge = clipboard;
    this.filePickerBridge = filePicker;
    this.screenCaptureBridge = screenCapture;
  }

  public async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'getClipboard') {
        const text = await this.clipboardBridge.getText();
        result.success(text);
      } else if (call.method === 'setClipboard') {
        const text: string = call.argument<string>('text') ?? '';
        const ok = await this.clipboardBridge.setText(text);
        result.success(ok);
      } else if (call.method === 'pickFiles') {
        if (this.filePickerBridge) {
          const files = await this.filePickerBridge.pickFiles();
          result.success(files);
        } else {
          result.success([]);
        }
      } else if (call.method === 'saveFile') {
        const fileName: string = call.argument<string>('fileName') ?? 'download';
        if (this.filePickerBridge) {
          const uri = await this.filePickerBridge.saveFile(fileName);
          result.success(uri);
        } else {
          result.success('');
        }
      } else if (call.method === 'startScreenCapture') {
        if (this.screenCaptureBridge) {
          const ok = await this.screenCaptureBridge.startCapture();
          result.success(ok);
        } else {
          result.success(false);
        }
      } else if (call.method === 'stopScreenCapture') {
        if (this.screenCaptureBridge) {
          const ok = await this.screenCaptureBridge.stopCapture();
          result.success(ok);
        } else {
          result.success(false);
        }
      } else {
        result.notImplemented();
      }
    } catch {
      result.error('ERROR', 'Method call execution failed');
    }
  }
}

export default class EntryAbility extends FlutterAbility {
  private clipboardBridge = ClipboardBridge.getInstance();
  private filePickerBridge: FilePickerBridge | null = null;
  private screenCaptureBridge: ScreenCaptureBridge | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);

    this.filePickerBridge = new FilePickerBridge(this.context);
    this.screenCaptureBridge = new ScreenCaptureBridge(this.context);

    const mChannel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), 'mChannel');
    this.clipboardBridge.init(mChannel);

    const handler = new RustDeskMethodHandler(
      this.clipboardBridge,
      this.filePickerBridge,
      this.screenCaptureBridge
    );
    mChannel.setMethodCallHandler(handler);
  }
}
