import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { setPeerAlias, setPeerOption, getPeerOption } from '../platform/RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskPeerEdit';

/**
 * The per-peer option keys the core stores a note under.
 *
 * Two keys because the account and this device each keep their own: `preset-note` is this
 * device's, and `preset-address-book-note` is what the account synced. Writing both is what makes
 * a note set here survive a restart and still be there when the account's book is re-fetched --
 * writing only the local one would be overwritten by the next sync.
 */
const OPTION_NOTE = 'preset-note';
const OPTION_AB_NOTE = 'preset-address-book-note';

/** A one-field text dialog, used for both renaming a device and editing its note. */
@CustomDialog
export struct PeerTextDialog {
  controller: CustomDialogController;
  /** The dialog's heading, e.g. "重命名". */
  title: string = '';
  /** The text the field starts with. */
  initial: string = '';
  /** Shown under the field; a hint rather than an error. */
  hint: string = '';
  /** Called with the trimmed text when the user confirms. */
  onSubmit: (value: string) => void = () => {};

  @State private value: string = '';

  aboutToAppear(): void {
    this.value = this.initial;
  }

  /**
   * Hand the text over and close.
   *
   * Guarded because the callback reaches the core: a throw inside a dialog callback would leave
   * the dialog open with no explanation, which reads as the button being broken.
   */
  private submit(): void {
    const text = this.value.trim();
    try {
      this.onSubmit(text);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'could not save: %{public}s', e instanceof Error ? e.message : String(e));
      promptAction.showToast({ message: '保存失败' });
      return;
    }
    this.controller.close();
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .width('100%')

      TextInput({ text: this.value, placeholder: this.hint })
        .width('100%')
        .height(48)
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.input_text'))
        .placeholderColor($r('app.color.input_placeholder'))
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius($r('app.float.radius_control'))
        .onChange((v: string) => {
          this.value = v;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.controller.close();
          })

        Button($r('app.string.common_confirm'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.brand'))
          .fontColor(Color.White)
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
  }
}

/** Set the local name for a device. */
export function applyAlias(id: string, alias: string): void {
  setPeerAlias(id, alias);
}

/** Read the note stored for a device, preferring the account's copy when there is one. */
export function readNote(id: string): string {
  const abNote = getPeerOption(id, OPTION_AB_NOTE);
  if (abNote.length > 0) {
    return abNote;
  }
  return getPeerOption(id, OPTION_NOTE);
}

/** Store a note for a device, under both keys so a sync does not lose it. */
export function writeNote(id: string, note: string): void {
  setPeerOption(id, OPTION_NOTE, note);
  setPeerOption(id, OPTION_AB_NOTE, note);
}
