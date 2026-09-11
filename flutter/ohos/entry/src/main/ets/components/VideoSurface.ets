import { hilog } from '@kit.PerformanceAnalysisKit';
import { videoAttachAndStart, videoDetach, DisplaySize } from '../platform/RustDeskBridge';
import { RemoteInput, RemoteButton, Modifiers, noModifiers, toRemotePoint } from '../platform/RemoteInput';

const DOMAIN = 0x0000;
const TAG = 'RustDeskVideo';

/** A tap moves the pointer less than this, in vp; more is treated as a drag. */
const TAP_SLOP_VP = 8;
/** A press held at least this long counts as a right click. */
const LONG_PRESS_MS = 500;
/** Distance per scroll notch, in vp. */
const SCROLL_NOTCH_VP = 40;

/**
 * The remote desktop surface, with touch input.
 *
 * An XComponent rather than an Image: ArkUI's PixelMap cannot signal that its contents changed,
 * so mutating one does not redraw, and building a new one per frame would allocate
 * `width * height * 4` every time -- around 8 MB per frame at 1080p. A surface is a buffer the
 * compositor owns and we write into, and the frames go there straight from Rust without crossing
 * the N-API boundary. See flutter/ohos/native/src/surface.rs for the drawing side.
 *
 * ### Touch mapping
 *
 * Touch is translated into mouse input, which is what a remote desktop expects: there is no way
 * to reach a desktop's pointer and menus from a touchscreen without a mouse model. The gestures
 * are the usual ones for a remote desktop client --
 *
 *   one finger drag        move the pointer (and drag, if it started as a press)
 *   tap                    left click
 *   long press             right click (menus)
 *   two finger drag        scroll
 *
 * Positions are converted into the peer's pixel space by RemoteInput. That conversion is the
 * part that is easy to get wrong, so it lives there and is clamped to the display.
 */
@Component
export struct VideoSurface {
  /** The session to draw. Empty means "show nothing yet". */
  @Prop sessionId: string = '';
  @Prop display: number = 0;
  /** Reported back so the page can show why there is no picture. */
  onError: (message: string) => void = () => {};
  /** The peer's desktop size, once known, so the page can show it. */
  onDisplaySize: (width: number, height: number) => void = () => {};

  private controller: XComponentController = new XComponentController();
  /** What the surface id was last bound for, so a rebind is not attempted needlessly. */
  private boundFor: string = '';
  /** Input for the current session; replaced when the session changes. */
  private input: RemoteInput | null = null;

  // Gesture state. Held as plain fields rather than @State: they change on every touch move, and
  // making them reactive would rebuild the surface on each frame of a drag.
  private downX: number = 0;
  private downY: number = 0;
  private lastX: number = 0;
  private lastY: number = 0;
  private downAtMs: number = 0;
  private dragging: boolean = false;
  private scrolled: boolean = false;
  private modifiers: Modifiers = noModifiers();

  /**
   * The surface's size in vp, from the component's layout.
   *
   * Reactive because a rotation or a fold changes it and the touch mapping depends on it, but it
   * only changes on layout, not per frame. There is no getter on the controller for this -- only
   * setters -- so the layout callback is the way to learn it.
   */
  @State private surfaceW: number = 0;
  @State private surfaceH: number = 0;

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
        this.input = null;
        videoDetach();
        this.boundFor = '';
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        // Touch coordinates are relative to this component and in vp, so the layout size is the
        // matching unit -- no conversion is needed, which is why this is the size to keep.
        this.surfaceW = Number(newValue.width);
        this.surfaceH = Number(newValue.height);
      })
      // --- gestures ---------------------------------------------------------
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
  }

  /**
   * Bind the surface and start the render loop for the current session.
   *
   * Safe to call repeatedly: it only acts when the session has actually changed, which matters
   * because onLoad and a resize both land here.
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
    this.input = new RemoteInput(this.sessionId);
    // The peer announces its display size a little after the first frame, so it is read here and
    // the page is told; input mapping does not depend on this having happened yet.
    const size = this.input.displaySize();
    if (size) {
      this.onDisplaySize(size.width, size.height);
    }
    hilog.info(DOMAIN, TAG, 'video attached for session %{public}s', this.sessionId);
  }

  /** Called by the page once the session exists, so the surface can be bound then. */
  attachIfNeeded(): void {
    this.attach();
  }

  /**
   * Translate a touch into remote input.
   *
   * A multi-touch gesture is treated as scrolling, because there is no second button on a
   * touchscreen and a two-finger drag is the conventional way to scroll a remote desktop. The
   * first finger of such a gesture must not also click, so anything that becomes a scroll
   * suppresses the click on release -- see `scrolled`.
   */
  private handleTouch(event: TouchEvent): void {
    const input = this.input;
    if (!input) {
      return;
    }
    const size = input.displaySize();
    if (!size) {
      // The peer has not announced its size yet, so there is nothing to map onto.
      return;
    }
    if (this.surfaceW <= 0 || this.surfaceH <= 0) {
      // The layout has not settled; the next event will have real numbers.
      return;
    }
    const rect: SurfaceRect = { w: this.surfaceW, h: this.surfaceH };

    const touch = event.touches.length > 0 ? event.touches[0] : undefined;
    if (!touch) {
      return;
    }
    const x = touch.x;
    const y = touch.y;

    switch (event.type) {
      case TouchType.Down:
        if (event.touches.length > 1) {
          // A second finger arrived: this is a scroll, not a click.
          this.scrolled = true;
          input.releaseAll(this.modifiers);
          break;
        }
        this.downX = x;
        this.downY = y;
        this.lastX = x;
        this.lastY = y;
        this.downAtMs = Date.now();
        this.dragging = false;
        this.scrolled = false;
        // Move the pointer to where the finger landed before pressing, so a tap lands where the
        // user aimed rather than wherever the pointer happened to be.
        this.sendMove(input, x, y, rect, size);
        break;

      case TouchType.Move:
        if (event.touches.length > 1 || this.scrolled) {
          // Two-finger drag scrolls. Whichever axis moved more is the one being scrolled; sending
          // both would scroll diagonally on a gesture the user meant as vertical.
          const dy = this.lastY - y;
          const dx = this.lastX - x;
          this.accumulateScroll(input, Math.abs(dy) > Math.abs(dx) ? dy : dx);
          this.lastX = x;
          this.lastY = y;
          break;
        }
        const movedFar = Math.abs(x - this.downX) > TAP_SLOP_VP ||
          Math.abs(y - this.downY) > TAP_SLOP_VP;
        if (!this.dragging && movedFar) {
          // The finger has travelled far enough to be a drag rather than a tap, so press the
          // button now and hold it: that is what makes dragging a window or selecting text work.
          this.dragging = true;
          input.down(RemoteButton.Left, this.modifiers);
        }
        this.sendMove(input, x, y, rect, size);
        this.lastX = x;
        this.lastY = y;
        break;

      case TouchType.Up:
        if (this.scrolled) {
          this.scrolled = false;
          break;
        }
        this.sendMove(input, x, y, rect, size);
        if (this.dragging) {
          input.up(RemoteButton.Left, this.modifiers);
        } else if (Date.now() - this.downAtMs >= LONG_PRESS_MS) {
          // Held without moving far: a right click, which is how the peer's context menus are
          // reached from a touchscreen.
          input.down(RemoteButton.Right, this.modifiers);
          input.up(RemoteButton.Right, this.modifiers);
        } else {
          input.down(RemoteButton.Left, this.modifiers);
          input.up(RemoteButton.Left, this.modifiers);
        }
        this.dragging = false;
        break;

      case TouchType.Cancel:
        // The gesture was taken away from us. Release whatever is held, or the peer keeps the
        // button down with no way to release it from this side.
        input.releaseAll(this.modifiers);
        this.dragging = false;
        this.scrolled = false;
        break;
    }
  }

  private sendMove(input: RemoteInput, x: number, y: number, rect: SurfaceRect,
                   size: DisplaySize): void {
    const point = toRemotePoint(x, y, rect.w, rect.h, size);
    if (point) {
      input.move(point, this.modifiers);
    }
  }

  /** Scroll by a pixel delta, converted into the notches the core expects. */
  private accumulateScroll(input: RemoteInput, deltaPx: number): void {
    // A notch per SCROLL_NOTCH_VP of travel, so a slow drag scrolls a little and a fast one more.
    // Rounded per event rather than accumulated: a sub-notch remainder is not worth carrying, and
    // carrying it would need state that has to be reset whenever a gesture starts.
    const notches = Math.round(deltaPx / SCROLL_NOTCH_VP);
    if (notches !== 0) {
      input.wheel(notches, this.modifiers);
    }
  }
}

interface SurfaceRect {
  w: number;
  h: number;
}
