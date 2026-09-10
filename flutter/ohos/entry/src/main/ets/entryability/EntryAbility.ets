import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ClipboardBridge } from '../platform/ClipboardBridge';
import { FilePickerBridge } from '../platform/FilePickerBridge';
import { ScreenCaptureBridge } from '../platform/ScreenCaptureBridge';
import { ConfigManager } from '../platform/ConfigStorage';

/**
 * Application entry.
 *
 * The window is laid out full screen, so the app draws beneath the status bar and the
 * gesture indicator instead of being letterboxed by them -- without this the system reserves
 * those bands and the page shows a strip of window background at the top and bottom. Pages
 * then take responsibility for keeping content clear of the bars via expandSafeArea, which is
 * what the HarmonyOS immersive guidance prescribes.
 */
export default class EntryAbility extends UIAbility {
  private clipboardBridge = ClipboardBridge.getInstance();
  private filePickerBridge: FilePickerBridge | null = null;
  private screenCaptureBridge: ScreenCaptureBridge | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Nothing ever opened the preferences store, so every read came back empty and every
    // save returned early -- which is why a self-hosted server appeared to save and then
    // showed as unset. This is the call that was missing.
    ConfigManager.getInstance().init(this.context);
    this.filePickerBridge = new FilePickerBridge(this.context);
    this.screenCaptureBridge = new ScreenCaptureBridge(this.context);
    this.clipboardBridge.init();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        return;
      }
      this.applyImmersiveWindow(windowStage);
    });
  }

  private applyImmersiveWindow(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    win.setWindowLayoutFullScreen(true).catch(() => {});

    // Bar icons have to contrast with our own background, not with a system-drawn bar, so
    // state which surface they sit on rather than leaving it to the default.
    win.setWindowSystemBarProperties({
      statusBarContentColor: '#000000',
      navigationBarContentColor: '#000000'
    }).catch(() => {});

    // A full-screen window means the page owns the areas the bars occupy, so it has to inset
    // its own content. Publishing the measurements keeps that arithmetic out of the layout
    // tree: the page reads these and pads. Values stay in px; the page converts.
    this.publishAvoidArea(win, window.AvoidAreaType.TYPE_SYSTEM, 'statusBarInsetPx');
    this.publishAvoidArea(win, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR, 'navIndicatorInsetPx');
  }

  private publishAvoidArea(win: window.Window, type: window.AvoidAreaType, key: string): void {
    const area = win.getWindowAvoidArea(type);
    const px = type === window.AvoidAreaType.TYPE_SYSTEM
      ? area.topRect.height
      : area.bottomRect.height;
    AppStorage.setOrCreate(key, px);
  }

  onDestroy(): void {
    if (this.screenCaptureBridge?.isRunning()) {
      this.screenCaptureBridge.stopCapture();
    }
  }
}
