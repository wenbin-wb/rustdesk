/**
 * A titled card, the standard container for grouped settings and status blocks.
 *
 * Exists so the padding, corner radius, surface colour and divider treatment are decided
 * once. Every value comes from a resource token, so light and dark are handled by the
 * `dark` resource qualifier rather than by a theme branch in code.
 */

@Component
export struct SectionCard {
  /** Section heading; omitted when empty, for a bare card. */
  @Prop title: ResourceStr = '';
  /** Optional short text on the trailing edge of the heading row. */
  @Prop trailing: ResourceStr = '';
  /** Optional status dot colour, shown left of the heading. */
  @Prop statusColor: ResourceColor = Color.Transparent;

  /** Card body. */
  @BuilderParam content: () => void;

  build() {
    Column({ space: 12 }) {
      if (this.title !== '') {
        Row({ space: 6 }) {
          if (this.statusColor !== Color.Transparent) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.statusColor)
          }
          Text(this.title)
            .fontSize($r('app.float.font_subtitle'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_title'))
          Blank()
          if (this.trailing !== '') {
            Text(this.trailing)
              .fontSize($r('app.float.font_caption'))
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
      }

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
  }
}
