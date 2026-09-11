import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClipboardBridge } from '../platform/ClipboardBridge';
import { FilePickerBridge } from '../platform/FilePickerBridge';
import { ScreenCaptureBridge } from '../platform/ScreenCaptureBridge';
import { ConfigManager } from '../platform/ConfigStorage';
import { initCore, getLastError } from '../platform/RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskCore';

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
    // Start the core first. Until it has a data directory it cannot persist anything, which
    // is why the device id used to change on every launch and why saved options were not
    // found on the next run. Everything below depends on a started core.
    this.startCore();

    // Nothing ever opened the preferences store, so every read came back empty and every
    // save returned early -- which is why a self-hosted server appeared to save and then
    // showed as unset. This is the call that was missing.
    ConfigManager.getInstance().init(this.context);
    this.filePickerBridge = new FilePickerBridge(this.context);
    this.screenCaptureBridge = new ScreenCaptureBridge(this.context);
    this.clipboardBridge.init();
  }

  /**
   * Hand the core its identity and working directory, then start it.
   *
   * `filesDir` is this application's own directory inside the sandbox and is the only place
   * the process may write, so it backs both the config path and the home path. Failures are
   * logged rather than thrown: a core that did not start still leaves a usable UI, and this
   * runs before the first frame.
   */
  private startCore(): void {
    try {
      const dir = this.context.filesDir;
      const name = this.context.applicationInfo?.label ?? 'RustDesk';
      initCore(dir, name);
      const err = getLastError();
      if (err.length > 0) {
        hilog.warn(DOMAIN, TAG, 'core reported an error after init: %{public}s', err);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'core init failed: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        return;
      }
      this.applyImmersiveWindow(windowStage);
    });
  }

  /**
   * Lay the window out full screen and publish the areas the page must inset against.
   *
   * Wrapped in try/catch as a whole: this is best-effort presentation, and it runs from the
   * loadContent callback, where a throw escapes. The per-call `.catch()` below only handles
   * async rejection -- getMainWindowSync and getWindowAvoidArea are flagged as throwing
   * synchronously, which `.catch()` does not cover. Cosmetics are not worth failing a launch
   * for, and the rest of the app already treats this as best-effort.
   */
  private applyImmersiveWindow(windowStage: window.WindowStage): void {
    try {
      const win = windowStage.getMainWindowSync();

      // Full screen layout is what stops the system reserving a strip for the bars, which is
      // what the window-coloured band at the top and bottom was.
      win.setWindowLayoutFullScreen(true).catch(() => {});

      // Bar icons sit on our own background rather than on a system-drawn bar, so state which
      // surface they are over rather than leaving it to the default. Unavailable on 2in1, where
      // there is no such bar.
      win.setWindowSystemBarProperties({
        statusBarContentColor: '#000000',
        navigationBarContentColor: '#000000'
      }).catch(() => {});

      // A full-screen window means the framework no longer insets content: measured on device,
      // the tab bar sat flush against y=2848, the last row of pixels. So the insets have to be
      // read and applied by the page. Publishing the raw px here keeps the window arithmetic in
      // the ability and the layout in the page.
      this.publishAvoidArea(win, window.AvoidAreaType.TYPE_SYSTEM, 'statusBarInsetPx');
      this.publishAvoidArea(win, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR, 'navIndicatorInsetPx');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'immersive window setup skipped: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * Publish one avoid area's height, in px, for the page to inset against.
   *
   * TYPE_SYSTEM is the status bar (its top rect); the navigation indicator is the gesture bar
   * at the bottom (its bottom rect). Anything not reported stays 0, so a device without one
   * simply gets no inset.
   *
   * Guarded per call rather than relying on the caller's try/catch. getWindowAvoidArea is
   * flagged as throwing, and if the first query threw, the second would never run -- leaving
   * the page with no top inset, i.e. the header under the status bar, which is the very defect
   * this was written to fix. One query failing must not cancel the other.
   */
  private publishAvoidArea(win: window.Window, type: window.AvoidAreaType, key: string): void {
    try {
      const area = win.getWindowAvoidArea(type);
      const height = type === window.AvoidAreaType.TYPE_SYSTEM
        ? area.topRect.height
        : area.bottomRect.height;
      AppStorage.setOrCreate(key, height);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'avoid area unavailable: %{public}s', key);
      // Explicit 0 rather than leaving the previous value: "no inset" is self-consistent.
      AppStorage.setOrCreate(key, 0);
    }
  }

  onDestroy(): void {
    if (this.screenCaptureBridge?.isRunning()) {
      this.screenCaptureBridge.stopCapture();
    }
  }
}
