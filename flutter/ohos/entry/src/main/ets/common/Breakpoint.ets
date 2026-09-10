/**
 * Layout breakpoints, following the HarmonyOS one-many (一多) adaptive conventions.
 *
 * Layout is driven by the window width rather than by device category, so the same page
 * serves phone, an unfolded foldable, a tablet and a 2in1 without per-device branches.
 * ArkUI's own `GridRow`/`GridCol` use these same thresholds, so a manual breakpoint read
 * here stays consistent with any Grid-based layout in the same page.
 *
 *   sm  width < 600vp    phone portrait        single column, bottom tab bar
 *   md  600 <= w < 840   phone landscape,      two columns: side rail + content
 *                        unfolded foldable
 *   lg  840 <= w < 1440  tablet                side rail + content, roomier spacing
 *   xl  width >= 1440    2in1 / desktop        as lg, with a wider content column
 *
 * `mediaquery` reports the current width and emits on every change, which is what makes a
 * fold/unfold reflow instead of requiring a rebuild. It is reached through
 * `UIContext.getMediaQuery()`: the module-level `mediaquery.matchMediaSync` was deprecated
 * in API 18 in favour of that path.
 */

import mediaquery from '@ohos.mediaquery';
import { UIContext } from '@kit.ArkUI';

export enum Breakpoint {
  Sm = 'sm',
  Md = 'md',
  Lg = 'lg',
  Xl = 'xl'
}

/** Ordered low to high, so comparisons read as "at least this wide". */
const ORDER: Breakpoint[] = [Breakpoint.Sm, Breakpoint.Md, Breakpoint.Lg, Breakpoint.Xl];

/** True when `current` is `target` or wider. */
export function atLeast(current: Breakpoint, target: Breakpoint): boolean {
  return ORDER.indexOf(current) >= ORDER.indexOf(target);
}

/**
 * True when the tab bar should sit at the side rather than the bottom.
 *
 * md is the threshold because that is where a two-column layout first fits comfortably;
 * below it a side rail would eat too much of a narrow window.
 */
export function usesSideNavigation(current: Breakpoint): boolean {
  return atLeast(current, Breakpoint.Md);
}

/**
 * Horizontal page padding, in vp, for the current breakpoint.
 */
export function pagePadding(current: Breakpoint): number {
  switch (current) {
    case Breakpoint.Sm:
      return 12;
    case Breakpoint.Md:
      return 16;
    case Breakpoint.Lg:
      return 24;
    default:
      return 32;
  }
}

/** Maximum content width, in vp, so text does not stretch on a 2in1 display. */
export function maxContentWidth(current: Breakpoint): number {
  switch (current) {
    case Breakpoint.Sm:
      return 600;
    case Breakpoint.Md:
      return 800;
    case Breakpoint.Lg:
      return 1000;
    default:
      return 1200;
  }
}

/**
 * Track the current breakpoint and re-emit on every window size change.
 *
 * `onChange` is called immediately with the current value, so a subscriber does not have
 * to seed its own state. Returns a disposer; call it from `aboutToDisappear`, otherwise
 * the listeners outlive the page and keep it referenced after it is gone.
 */
export function observeBreakpoint(uiContext: UIContext,
                                  onChange: (bp: Breakpoint) => void): () => void {
  const listeners: Array<() => void> = [];
  const mediaQuery = uiContext.getMediaQuery();

  // One listener per breakpoint rather than a single width listener: mediaquery matches
  // against a predicate, and taking the widest match avoids re-deriving the band from a
  // raw width at each call site.
  const register = (bp: Breakpoint, condition: string): void => {
    const listener = mediaQuery.matchMediaSync(condition);
    const cb = (result: mediaquery.MediaQueryResult): void => {
      if (result.matches) {
        onChange(bp);
      }
    };
    listener.on('change', cb);
    listeners.push(() => listener.off('change', cb));
    if (listener.matches) {
      onChange(bp);
    }
  };

  register(Breakpoint.Sm, '(width<600vp)');
  register(Breakpoint.Md, '(600vp<=width<840vp)');
  register(Breakpoint.Lg, '(840vp<=width<1440vp)');
  register(Breakpoint.Xl, '(width>=1440vp)');

  return () => {
    listeners.forEach((off) => off());
  };
}
