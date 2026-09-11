import { DisplaySize, getDisplaySize, sendMouse, inputKey, inputString } from './RustDeskBridge';

/**
 * Turns touch gestures on the surface into the core's input messages.
 *
 * The message shapes are the core's own contract and are all strings, which is easy to get
 * subtly wrong from several call sites -- `session_send_mouse` in src/flutter_ffi.rs documents
 * them -- so they are built here and nowhere else.
 *
 * ### Coordinate spaces
 *
 * Mouse events carry positions in the *peer's* pixels, not the surface's. A touch lands in
 * surface pixels, so it is scaled by `displaySize / surfaceSize` before being sent. Without that
 * the pointer lands in the wrong place whenever the two differ, which is almost always: a phone
 * surface is not the shape of a desktop.
 *
 * The scale factor is recomputed on each gesture rather than cached, because the surface is
 * re-laid out on rotation and on a fold, and a stale factor would misplace every touch after it.
 */

/** Which mouse buttons the core accepts, by the name it expects. */
export enum RemoteButton {
  Left = 'left',
  Right = 'right',
  Wheel = 'wheel'
}

/** A pointer position in the peer's pixels. */
export interface RemotePoint {
  x: number;
  y: number
}

/**
 * The core's mouse message shape.
 *
 * Declared as an interface because ArkTS requires an object literal to correspond to a named type;
 * every field is a string, including the numbers, because that is what the core parses.
 */
interface MouseMessage {
  type: string;
  x?: string;
  y?: string;
  buttons?: string;
  ctrl?: string;
  shift?: string;
  alt?: string;
  command?: string;
}

/** Modifier state, as held during the current gesture. */
export interface Modifiers {
  ctrl: boolean;
  shift: boolean;
  alt: boolean;
  command: boolean;
}

export function noModifiers(): Modifiers {
  return { ctrl: false, shift: false, alt: false, command: false };
}

/**
 * Map a point on the surface to the peer's coordinate space.
 *
 * Clamped to the display: a drag can leave the surface, and a negative or out-of-range position
 * would move the peer's pointer somewhere the user cannot see.
 */
export function toRemotePoint(x: number, y: number, surfaceWidth: number, surfaceHeight: number,
                              display: DisplaySize | undefined): RemotePoint | null {
  if (!display || display.width === 0 || display.height === 0) {
    return null;
  }
  if (surfaceWidth <= 0 || surfaceHeight <= 0) {
    return null;
  }
  const rx = Math.round(x * display.width / surfaceWidth);
  const ry = Math.round(y * display.height / surfaceHeight);
  return {
    x: Math.min(Math.max(rx, 0), display.width - 1),
    y: Math.min(Math.max(ry, 0), display.height - 1)
  };
}

/** Attach the held modifiers, matching what the Flutter client does. */
function applyModifiers(msg: MouseMessage, mods: Modifiers): MouseMessage {
  if (mods.ctrl) { msg.ctrl = 'true'; }
  if (mods.shift) { msg.shift = 'true'; }
  if (mods.alt) { msg.alt = 'true'; }
  if (mods.command) { msg.command = 'true'; }
  return msg;
}

/**
 * Sends input to one session.
 *
 * Constructed per session page and used only while the session is live, so it holds no state that
 * could outlive the connection it belongs to.
 */
export class RemoteInput {
  private sessionId: string;
  /** The button currently held, if any, so a move reports the same button as its press. */
  private heldButton: string = '';

  constructor(sessionId: string) {
    this.sessionId = sessionId;
  }

  /** The peer's display size, or undefined until the peer announces it. */
  displaySize(): DisplaySize | undefined {
    try {
      return getDisplaySize(this.sessionId, 0);
    } catch (e) {
      return undefined;
    }
  }

  /** Move the peer's pointer to an absolute position. */
  move(point: RemotePoint, mods: Modifiers): void {
    const msg: MouseMessage = {
      type: 'mousemove',
      x: point.x.toString(),
      y: point.y.toString(),
      // The core expects the held button on a move so a drag is distinguishable from a hover.
      buttons: this.heldButton
    };
    this.send(applyModifiers(msg, mods));
  }

  /** Press a button at the current position. */
  down(button: RemoteButton, mods: Modifiers): void {
    this.heldButton = button;
    this.send(applyModifiers({ type: 'mousedown', buttons: button }, mods));
  }

  /** Release a button. */
  up(button: RemoteButton, mods: Modifiers): void {
    if (this.heldButton === button) {
      this.heldButton = '';
    }
    this.send(applyModifiers({ type: 'mouseup', buttons: button }, mods));
  }

  /**
   * Release whatever is held.
   *
   * Called when a gesture is interrupted -- a cancellation, or the surface going away -- because
   * a button left down on the peer keeps it held there with no way to release it from this side.
   */
  releaseAll(mods: Modifiers): void {
    if (this.heldButton.length > 0) {
      this.up(this.heldButton as RemoteButton, mods);
    }
  }

  /** Scroll. `ticks` is positive for down/right. */
  wheel(ticks: number, mods: Modifiers): void {
    this.send(applyModifiers({ type: 'wheel', y: ticks.toString() }, mods));
  }

  /**
   * Send a key by name.
   *
   * `press` sends a complete press and release in one message, which is what a soft keyboard
   * wants; it has no way to report a release separately.
   */
  key(name: string, press: boolean, mods: Modifiers): void {
    try {
      // `down` is the inverse of `press`: a press already carries its own release.
      inputKey(this.sessionId, name, !press, press, mods.alt, mods.ctrl, mods.shift, mods.command);
    } catch (e) {
      // Nothing useful to do: the session is gone or the name is unknown to the core.
    }
  }

  /**
   * Send typed text.
   *
   * Preferred over per-key messages: it is one message, and the peer receives the text rather
   * than a sequence of keys, so it does not depend on the peer's keyboard layout.
   */
  text(value: string): void {
    if (value.length === 0) {
      return;
    }
    try {
      inputString(this.sessionId, value);
    } catch (e) {
      // As above.
    }
  }

  private send(msg: MouseMessage): void {
    try {
      sendMouse(this.sessionId, JSON.stringify(msg));
    } catch (e) {
      // A dropped input event is not worth failing the session over; the next one will follow.
    }
  }
}
