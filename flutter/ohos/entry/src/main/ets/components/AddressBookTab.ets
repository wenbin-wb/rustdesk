import { ChipGroup, ChipGroupItemOptions, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  loadAddressBook, loadFavouritePeerIds, loadStoredPeers, queryOnlines, pollUiEvents,
  peerHasPassword, AddressBook, AbPeer, StoredPeerInfo
} from '../platform/RustDeskBridge';
import { PeerTextDialog, applyAlias, readNote, writeNote } from './PeerTextDialog';

const DOMAIN = 0x0000;
const TAG = 'RustDeskAddressBook';

/** How often the server is asked which peers are online. */
const ONLINE_POLL_MS = 15000;
/** How often the queue is checked for the answer. Much shorter, since the answer is prompt. */
const EVENT_POLL_MS = 500;

/**
 * The gap between device cards.
 *
 * Set on each ListItemGroup rather than on the List: `List({ space })` separates only the items
 * sitting directly in the list, so with every device inside a group it had no effect at all and
 * the cards rendered flush against each other as one continuous white block.
 */
const ROW_GAP = 12;

/** One device, flattened from whichever source it came from. */
interface PeerRow {
  id: string;
  /** The line to show: an alias if the user set one, else the device name, else the id. */
  title: string;
  /** The device name, shown under the title when the title is an alias. */
  hostname: string;
  /** The peer's platform, for the icon. */
  platform: string;
  /** Whether a password is held for this device. */
  hasPassword: boolean;
}

/** One address book, and the devices in it. */
interface PeerGroup {
  name: string;
  peers: PeerRow[];
}

const TAB_ADDRESS_BOOK = 0;
const TAB_FAVOURITES = 1;
const TAB_RECENT = 2;

/**
 * The address book, favourites and recent devices.
 *
 * All three are read from the core, which is where the account syncs into and where every alias,
 * note, remembered password and favourite lives.
 *
 * A row carries what the original client's card carries, because those are what a user picks a
 * device by: an icon for the platform, the device's name -- the user's own name for it when they
 * have set one -- its id, and whether it is reachable right now.
 */
@Component
export struct AddressBookTab {
  @Prop @Watch('onRevisionChanged') peersRevision: number = 0;

  /**
   * How much room to leave at the end of the list for the floating bar.
   *
   * Supplied by the page because it depends on the layout band: the bar is taller at the bottom of
   * a phone than it is on the side of a tablet. It is applied as a list content offset rather than
   * as padding on the container, so the list still runs to the screen edge and its content passes
   * under the bar.
   */
  @Prop contentBottomInset: number = 104;

  onConnect: (targetId: string) => void = () => {};

  @State private groups: PeerGroup[] = [];
  @State private favourites: PeerRow[] = [];
  @State private recent: PeerRow[] = [];
  @State private subTab: number = TAB_ADDRESS_BOOK;
  @State private query: string = '';
  @State private signedIn: boolean = false;
  /**
   * Which devices the server reported as online.
   *
   * Keyed by id rather than stored on the rows, because the answer arrives separately from the
   * lists, and writing a flag into every row would rebuild the whole list on each poll.
   */
  @State private online: Record<string, boolean> = {};

  private onlineTimerId: number = -1;
  private eventTimerId: number = -1;
  private editDialog: CustomDialogController | null = null;
  @State private editTitle: string = '';
  @State private editInitial: string = '';
  @State private editHint: string = '';
  private editTargetId: string = '';
  private editIsNote: boolean = false;

  aboutToAppear(): void {
    this.reload();
    this.eventTimerId = setInterval(() => {
      this.drainEvents();
    }, EVENT_POLL_MS);
    this.onlineTimerId = setInterval(() => {
      this.askWhoIsOnline();
    }, ONLINE_POLL_MS);
  }

  aboutToDisappear(): void {
    if (this.onlineTimerId !== -1) {
      clearInterval(this.onlineTimerId);
      this.onlineTimerId = -1;
    }
    if (this.eventTimerId !== -1) {
      clearInterval(this.eventTimerId);
      this.eventTimerId = -1;
    }
  }

  onRevisionChanged(): void {
    this.reload();
  }

  /**
   * Read all three lists, then ask who is online.
   *
   * Each source is read in its own guarded step: they are separate calls into the core and any of
   * them can fail on its own, so one failing must not cost the other two -- and the log has to say
   * which one.
   */
  private reload(): void {
    try {
      const book: AddressBook = loadAddressBook();
      this.signedIn = (book.access_token ?? '').length > 0;
      this.groups = groupOf(book);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'address book unreadable: %{public}s', messageOf(e));
    }
    try {
      this.favourites = favouritesOf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'favourites unreadable: %{public}s', messageOf(e));
    }
    try {
      this.recent = recentOf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'recent peers unreadable: %{public}s', messageOf(e));
    }
    this.askWhoIsOnline();
  }

  /**
   * Ask the server which of the listed devices are online.
   *
   * Nothing comes back from the call, so the answer is picked up in {@link drainEvents}. Asking
   * about only the ids on screen keeps the query small, and asking about none would be a wasted
   * round trip.
   */
  private askWhoIsOnline(): void {
    try {
      const ids = this.allIds();
      if (ids.length > 0) {
        queryOnlines(ids);
      }
    } catch (e) {
      // Presence is best effort: the list is usable without it, and an error here would be noise
      // on a device that is simply offline.
      hilog.debug(DOMAIN, TAG, 'online query skipped: %{public}s', messageOf(e));
    }
  }

  /** Every id currently listed, across all three sources, without duplicates. */
  private allIds(): string[] {
    const seen: Record<string, boolean> = {};
    const out: string[] = [];
    const add = (rows: PeerRow[]): void => {
      for (const row of rows) {
        if (row.id.length > 0 && !seen[row.id]) {
          seen[row.id] = true;
          out.push(row.id);
        }
      }
    };
    for (const group of this.groups) {
      add(group.peers);
    }
    add(this.favourites);
    add(this.recent);
    return out;
  }

  /**
   * Read the core's queued events and apply the presence answer.
   *
   * The queue is shared with the remote-session page, which is why everything unrecognised is left
   * alone rather than discarded. The two screens are never on display at once, so neither can take
   * an event the other needed.
   */
  private drainEvents(): void {
    let events: string[] = [];
    try {
      events = pollUiEvents();
    } catch (e) {
      return;
    }
    for (const event of events) {
      if (event.indexOf('callback_query_onlines') < 0) {
        continue;
      }
      try {
        const parsed = JSON.parse(event) as OnlineEvent;
        // Rebuilt rather than merged, so a device that has gone offline since the last answer is
        // cleared instead of keeping its old state.
        const next: Record<string, boolean> = {};
        for (const id of splitIds(parsed.onlines)) {
          next[id] = true;
        }
        for (const id of splitIds(parsed.offlines)) {
          next[id] = false;
        }
        this.online = next;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'could not read presence: %{public}s', messageOf(e));
      }
    }
  }

  private visibleGroups(): PeerGroup[] {
    const wanted = this.query.trim().toLowerCase();
    let source: PeerGroup[];
    if (this.subTab === TAB_FAVOURITES) {
      source = [{ name: '', peers: this.favourites } as PeerGroup];
    } else if (this.subTab === TAB_RECENT) {
      source = [{ name: '', peers: this.recent } as PeerGroup];
    } else {
      source = this.groups;
    }
    if (wanted.length === 0) {
      return source.filter((group: PeerGroup) => group.peers.length > 0);
    }
    const out: PeerGroup[] = [];
    for (const group of source) {
      const matched: PeerRow[] = [];
      for (const peer of group.peers) {
        // The device name and the account's own name for it are both worth matching, because a
        // user may have either in mind.
        if (peer.title.toLowerCase().includes(wanted) ||
            peer.hostname.toLowerCase().includes(wanted) ||
            peer.id.includes(wanted)) {
          matched.push(peer);
        }
      }
      if (matched.length > 0) {
        out.push({ name: group.name, peers: matched });
      }
    }
    return out;
  }

  private hasAnyPeer(): boolean {
    return this.groups.length > 0 || this.favourites.length > 0 || this.recent.length > 0;
  }

  // --- dialogs ----------------------------------------------------------------

  private openRename(peer: PeerRow): void {
    this.editIsNote = false;
    this.editTargetId = peer.id;
    this.editTitle = '重命名';
    this.editInitial = peer.title;
    this.editHint = '输入新名称';
    this.showEditDialog();
  }

  private openNote(peer: PeerRow): void {
    this.editIsNote = true;
    this.editTargetId = peer.id;
    this.editTitle = '备注';
    this.editInitial = '';
    this.editHint = '为这台设备写点备注';
    try {
      this.editInitial = readNote(peer.id);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not read the note: %{public}s', messageOf(e));
    }
    this.showEditDialog();
  }

  /**
   * Open the edit dialog.
   *
   * The controller is rebuilt for each open so it captures the peer being edited; one long-lived
   * controller would keep whichever peer it was first given.
   */
  private showEditDialog(): void {
    this.editDialog = new CustomDialogController({
      builder: PeerTextDialog({
        title: this.editTitle,
        initial: this.editInitial,
        hint: this.editHint,
        onSubmit: (value: string) => {
          this.saveEdit(value);
        }
      }),
      // Without this the framework wraps the content in its own opaque container, which shows as
      // a white rim around the dialog.
      customStyle: true,
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.editDialog.open();
  }

  private saveEdit(value: string): void {
    try {
      if (this.editIsNote) {
        writeNote(this.editTargetId, value);
      } else {
        applyAlias(this.editTargetId, value);
      }
      promptAction.showToast({ message: '已保存' });
      this.reload();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'could not save: %{public}s', messageOf(e));
      promptAction.showToast({ message: '保存失败' });
    }
  }

  // --- view -------------------------------------------------------------------

  build() {
    Column({ space: 12 }) {
      this.buildSubTabs()
      this.buildSearch()

      if (!this.hasAnyPeer() && !this.signedIn) {
        this.buildEmptyState($r('app.string.ab_signed_out'), $r('app.string.ab_signed_out_hint'))
      } else if (this.visibleGroups().length === 0) {
        this.buildEmptyState(
          this.query.length > 0 ? $r('app.string.ab_no_match') : $r('app.string.ab_empty'),
          this.query.length > 0 ? $r('app.string.ab_no_match_hint') : $r('app.string.ab_empty_hint')
        )
      } else {
        this.buildList()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSubTabs() {
    ChipGroup({
      items: [
        { label: { text: '地址簿' } } as ChipGroupItemOptions,
        { label: { text: '收藏' } } as ChipGroupItemOptions,
        { label: { text: '最近' } } as ChipGroupItemOptions
      ],
      selectedIndexes: [this.subTab],
      onChange: (indexes: Array<number>) => {
        if (indexes.length > 0) {
          this.subTab = indexes[0];
        }
      }
    })
      .width('100%')
  }

  @Builder
  private buildSearch() {
    Search({ value: this.query, placeholder: '搜索设备' })
      .width('100%')
      .height(40)
      .backgroundColor($r('app.color.bg_card'))
      .placeholderColor($r('app.color.input_placeholder'))
      .textFont({ size: $r('app.float.font_body') })
      .onChange((value: string) => {
        this.query = value;
      })
  }

  /**
   * The list, one group per address book.
   *
   * `ListItemGroup` gives the book headings. The spacing that separates the cards is set on the
   * GROUP, not on the List: `List({ space })` only separates items sitting directly in the list,
   * so with every device inside a group it had no effect at all and the cards rendered flush
   * against each other as one continuous white block.
   */
  @Builder
  private buildList() {
    List() {
      ForEach(this.visibleGroups(), (group: PeerGroup) => {
        ListItemGroup({ header: this.buildGroupHeader(group.name), space: ROW_GAP })
          .backgroundColor(Color.Transparent)
          .borderRadius($r('app.float.radius_control'))
          .clip(false) {
          ForEach(group.peers, (peer: PeerRow) => {
            ListItem() {
              this.buildRow(peer)
            }
            // Slide a row leftwards to reveal its actions, which is how the platform expects
            // per-item actions to be offered and keeps them off the card itself.
            .swipeAction({ end: this.buildSwipeActions(peer) })
          }, (peer: PeerRow) => peer.id)
        }
      }, (group: PeerGroup) => `${group.name}:${group.peers.length}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // The cards carry their own background, so the list must not paint over the gaps between
    // them -- a list background here is what turned the spacing invisible.
    .backgroundColor(Color.Transparent)
    // Room for the floating bar, added INSIDE the list rather than by shrinking it. The list still
    // reaches the bottom of the screen, so cards scroll underneath the bar and its translucent
    // material has content to blur -- which is the whole point of a floating bar. Insetting the
    // container instead left the bar sitting over empty background, where it read as a solid band.
    .contentEndOffset(this.contentBottomInset)
  }

  /** The actions revealed by sliding a row. */
  @Builder
  buildSwipeActions(peer: PeerRow) {
    Row() {
      this.buildSwipeButton('重命名', $r('app.color.brand'), () => {
        this.openRename(peer);
      })
      this.buildSwipeButton('备注', $r('app.color.text_secondary'), () => {
        this.openNote(peer);
      })
    }
    .height('100%')
  }

  @Builder
  buildSwipeButton(label: string, color: Resource, action: () => void) {
    Text(label)
      .fontSize($r('app.float.font_caption'))
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(76)
      .height('100%')
      .backgroundColor(color)
      .borderRadius($r('app.float.radius_control'))
      .margin({ left: 6 })
      .onClick(() => {
        action();
      })
  }

  @Builder
  private buildGroupHeader(name: string) {
    // A single-book list does not need a heading saying which book it is; the sub-tab already says
    // that, and a heading above a lone group is noise.
    if (name.length === 0 || this.visibleGroups().length < 2) {
      Row().height(4)
    } else {
      Text(name)
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 4, top: 10, bottom: 4 })
    }
  }

  /**
   * One device.
   *
   * The icon identifies the platform at a glance, which is how the original client lets a user
   * pick between several machines without reading every name. The dot is the presence the server
   * reported and sits at the end of the row: it changes on its own, and putting it beside the name
   * would shift the text every time a device came online.
   */
  @Builder
  private buildRow(peer: PeerRow) {
    Row({ space: 12 }) {
      Image(platformIcon(peer.platform))
        .width(34)
        .height(34)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.text_secondary'))
        .flexShrink(0)

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(peer.title)
            .fontSize($r('app.float.font_body'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (peer.hasPassword) {
            // The original marks devices it holds a password for, so a user can tell which will
            // connect without being asked.
            SymbolGlyph($r('sys.symbol.key'))
              .fontSize(14)
              .fontColor([$r('app.color.text_hint')])
          }
        }
        .width('100%')

        Text(peer.hostname.length > 0 && peer.hostname !== peer.title
          ? `${peer.hostname} · ${peer.id}`
          : peer.id)
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Circle()
        .width(8)
        .height(8)
        .fill(this.online[peer.id] === true
          ? $r('app.color.status_online')
          : $r('app.color.text_hint'))
        .flexShrink(0)

      // The row's own tap connects, so the menu is the only other action and stays a small target
      // at the end where it cannot be hit while reaching for the row.
      Text('⋮')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 6, right: 2 })
        .bindMenu(this.peerMenu(peer))
        .flexShrink(0)
    }
    .width('100%')
    .padding({ left: 14, right: 10, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_control'))
    .onClick(() => {
      this.onConnect(peer.id);
    })
  }

  /** The per-device actions, as a menu rather than a row of buttons. */
  private peerMenu(peer: PeerRow): MenuElement[] {
    return [
      {
        value: '重命名',
        action: () => {
          this.openRename(peer);
        }
      },
      {
        value: '备注',
        action: () => {
          this.openNote(peer);
        }
      },
      {
        value: '连接',
        action: () => {
          this.onConnect(peer.id);
        }
      }
    ];
  }

  @Builder
  private buildEmptyState(title: ResourceStr, hint: ResourceStr) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.text_secondary'))
      Text(hint)
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_hint'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48, left: 16, right: 16 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius($r('app.float.radius_card'))
  }
}

/** The presence event the core queues. */
interface OnlineEvent {
  name?: string;
  /** Ids that are online, comma separated. */
  onlines?: string;
  /** Ids that are not, comma separated. */
  offlines?: string;
}

// --- shaping ------------------------------------------------------------------

/**
 * A description of a thrown value.
 *
 * Not JSON.stringify: an Error's message and stack are not enumerable, so stringifying one yields
 * "{}" -- which is how a real failure here was once logged as nothing at all.
 */
function messageOf(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  const text = String(e);
  return text.length > 0 ? text : 'unknown error';
}

/** Split a comma-separated id list, dropping empties. */
function splitIds(csv: string | undefined): string[] {
  if (!csv) {
    return [];
  }
  const out: string[] = [];
  for (const part of csv.split(',')) {
    const id = part.trim();
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

/** The icon for a platform. An unknown platform still gets one, so the rows stay aligned. */
function platformIcon(platform: string): Resource {
  if (platform === 'Windows') {
    return $r('app.media.platform_win');
  }
  if (platform === 'Mac OS') {
    return $r('app.media.platform_mac');
  }
  if (platform === 'Android') {
    return $r('app.media.platform_android');
  }
  return $r('app.media.platform_linux');
}

/** The address book, one group per book, skipping empty books. */
function groupOf(book: AddressBook): PeerGroup[] {
  const groups: PeerGroup[] = [];
  for (const entry of (book.ab_entries ?? [])) {
    const peers: PeerRow[] = [];
    for (const peer of (entry.peers ?? [])) {
      // An entry with no id cannot be connected to, so it is not a row.
      if ((peer.id ?? '').length > 0) {
        peers.push(rowOf(peer));
      }
    }
    if (peers.length > 0) {
      groups.push({ name: entry.name ?? '', peers: peers });
    }
  }
  return groups;
}

/**
 * One address-book entry as a row.
 *
 * Every field is read through `?? ''`: the core omits empty fields from its JSON rather than
 * sending them empty, so any of these can be absent at runtime however the interface reads.
 */
function rowOf(peer: AbPeer): PeerRow {
  const id = peer.id ?? '';
  const alias = peer.alias ?? '';
  const hostname = peer.hostname ?? '';
  let hasPassword = false;
  try {
    hasPassword = peerHasPassword(id);
  } catch (e) {
    hasPassword = false;
  }
  return {
    id: id,
    title: alias.length > 0 ? alias : (hostname.length > 0 ? hostname : id),
    hostname: hostname,
    platform: peer.platform ?? '',
    hasPassword: hasPassword
  };
}

/** The favourited devices, taken from the address book by id. */
function favouritesOf(): PeerRow[] {
  const ids = loadFavouritePeerIds();
  if (ids.length === 0) {
    return [];
  }
  const rows: PeerRow[] = [];
  const book = loadAddressBook();
  const entries = book.ab_entries ?? [];
  for (const id of ids) {
    let found: AbPeer | undefined = undefined;
    for (const entry of entries) {
      for (const peer of (entry.peers ?? [])) {
        if ((peer.id ?? '') === id) {
          found = peer;
          break;
        }
      }
      if (found) {
        break;
      }
    }
    // A favourite can outlive its address-book entry -- the device may have been removed from the
    // account but not from this device's favourites -- so a missing one still gets a row rather
    // than being dropped silently.
    rows.push(found ? rowOf(found) : {
      id: id, title: id, hostname: '', platform: '', hasPassword: false
    });
  }
  return rows;
}

/** Devices connected from this device, which the core keeps separately from the account. */
function recentOf(): PeerRow[] {
  const rows: PeerRow[] = [];
  const peers: StoredPeerInfo[] = loadStoredPeers([]);
  for (const peer of peers) {
    const id = peer.id ?? '';
    if (id.length === 0) {
      continue;
    }
    const alias = peer.alias ?? '';
    const hostname = peer.hostname ?? '';
    let hasPassword = false;
    try {
      hasPassword = peerHasPassword(id);
    } catch (e) {
      hasPassword = false;
    }
    rows.push({
      id: id,
      title: alias.length > 0 ? alias : (hostname.length > 0 ? hostname : id),
      hostname: hostname,
      platform: peer.platform ?? '',
      hasPassword: hasPassword
    });
  }
  return rows;
}
