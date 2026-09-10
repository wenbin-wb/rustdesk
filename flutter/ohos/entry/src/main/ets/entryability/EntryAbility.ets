import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ClipboardBridge } from '../platform/ClipboardBridge';
import { FilePickerBridge } from '../platform/FilePickerBridge';
import { ScreenCaptureBridge } from '../platform/ScreenCaptureBridge';

export default class EntryAbility extends UIAbility {
  private clipboardBridge = ClipboardBridge.getInstance();
  private filePickerBridge: FilePickerBridge | null = null;
  private screenCaptureBridge: ScreenCaptureBridge | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.filePickerBridge = new FilePickerBridge(this.context);
    this.screenCaptureBridge = new ScreenCaptureBridge(this.context);
    this.clipboardBridge.init();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }

  onDestroy(): void {
    if (this.screenCaptureBridge?.isRunning()) {
      this.screenCaptureBridge.stopCapture();
    }
  }
}

