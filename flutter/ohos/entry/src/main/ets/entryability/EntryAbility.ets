import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { ClipboardBridge } from '../platform/ClipboardBridge';
import { FilePickerBridge } from '../platform/FilePickerBridge';
import { ScreenCaptureBridge } from '../platform/ScreenCaptureBridge';

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

    mChannel.setMethodCallHandler({
      onMethodCall: async (call: MethodCall, result: MethodResult) => {
        try {
          switch (call.method) {
            case 'getClipboard': {
              const text = await this.clipboardBridge.getText();
              result.success(text);
              break;
            }
            case 'setClipboard': {
              const text = call.argument('text') as string ?? '';
              const ok = await this.clipboardBridge.setText(text);
              result.success(ok);
              break;
            }
            case 'pickFiles': {
              if (this.filePickerBridge) {
                const files = await this.filePickerBridge.pickFiles();
                result.success(files);
              } else {
                result.success([]);
              }
              break;
            }
            case 'saveFile': {
              const fileName = call.argument('fileName') as string ?? 'download';
              if (this.filePickerBridge) {
                const uri = await this.filePickerBridge.saveFile(fileName);
                result.success(uri);
              } else {
                result.success('');
              }
              break;
            }
            case 'startScreenCapture': {
              if (this.screenCaptureBridge) {
                const ok = await this.screenCaptureBridge.startCapture();
                result.success(ok);
              } else {
                result.success(false);
              }
              break;
            }
            case 'stopScreenCapture': {
              if (this.screenCaptureBridge) {
                const ok = await this.screenCaptureBridge.stopCapture();
                result.success(ok);
              } else {
                result.success(false);
              }
              break;
            }
            default:
              result.notImplemented();
              break;
          }
        } catch {
          result.error('ERROR', 'Method call execution failed', null);
        }
      }
    });
  }
}
