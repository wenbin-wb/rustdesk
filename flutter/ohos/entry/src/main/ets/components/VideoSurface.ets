import { hilog } from '@kit.PerformanceAnalysisKit';
import { videoAttachAndStart, videoDetach } from '../platform/RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskVideo';

/**
 * The remote desktop surface.
 *
 * An XComponent rather than an Image: ArkUI's PixelMap cannot signal that its contents changed,
 * so mutating one does not redraw, and building a new one per frame would allocate `width * height
 * * 4` every time -- around 8 MB per frame at 1080p. A surface is a buffer the compositor owns and
 * we write into, and the frames go there straight from Rust without crossing the N-API boundary.
 *
 * See flutter/ohos/native/src/surface.rs for the drawing side.
 */


@Component
export struct VideoSurface {
  /** The session to draw. Empty means "show nothing yet". */
  @Prop sessionId: string = '';
  @Prop display: number = 0;
  /** Reported back so the page can show why there is no picture. */
  onError: (message: string) => void = () => {};

  private controller: XComponentController = new XComponentController();
  /** What the surface id was last bound for, so a rebind is not attempted needlessly. */
  private boundFor: string = '';

  build() {
    XComponent({
      id: 'rustdesk_surface',
      type: XComponentType.SURFACE,
      controller: this.controller
    })
      .width('100%')
      .height('100%')
      .onLoad(() => {
        // The surface exists from here on. Binding is deferred to `attach`, which the page calls
        // once the core has a session, because drawing before then has nothing to draw.
        this.attach();
      })
      .onDestroy(() => {
        videoDetach();
        this.boundFor = '';
      })
  }

  /**
   * Bind the surface and start the render loop for the current session.
   *
   * Safe to call repeatedly: it only acts when the session or the surface has actually changed,
   * which matters because onLoad and a resize both land here.
   */
  attach(): void {
    if (this.sessionId.length === 0) {
      return;
    }
    if (this.boundFor === this.sessionId) {
      return;
    }
    // getXComponentSurfaceId returns a decimal string; the core parses it. Re-reading it here
    // rather than caching from onLoad keeps this correct across a surface recreation.
    const surfaceId = this.controller.getXComponentSurfaceId();
    if (!surfaceId || surfaceId.length === 0) {
      this.onError('surface is not ready');
      return;
    }
    const err = videoAttachAndStart(surfaceId, this.sessionId, this.display);
    if (err.length > 0) {
      hilog.warn(DOMAIN, TAG, 'could not start video: %{public}s', err);
      this.onError(err);
      return;
    }
    this.boundFor = this.sessionId;
    hilog.info(DOMAIN, TAG, 'video attached for session %{public}s', this.sessionId);
  }

  /** Called by the page once the session exists, so the surface can be bound then. */
  attachIfNeeded(): void {
    this.attach();
  }
}
