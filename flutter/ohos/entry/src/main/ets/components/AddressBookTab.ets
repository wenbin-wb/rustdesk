import { HdsListItemCard } from '@kit.UIDesignKit';
import { ChipGroup, ChipGroupItemOptions, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  loadAddressBook, loadFavouritePeerIds, loadStoredPeers, AddressBook, AbEntry, AbPeer,
  StoredPeerInfo
} from '../platform/RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskAddressBook';

/**
 * The address book, favourites and recent devices.
 *
 * All three come from the core, which is where the account syncs into and where every alias,
 * remembered password and favourite is stored. Nothing here keeps its own copy: a second list in
 * the front end would be a second answer to "which devices do I have", and the two would drift.
 *
 * Built from the platform's own components rather than from layout primitives -- `ChipGroup` for
 * the sub-tabs, `List`/`ListItemGroup` for the list so it gets the platform's scrolling, sticky
 * headers and recycling, `Search` for filtering, and the system toast for feedback. Hand-rolled
 * equivalents of these are what the earlier revision used, and they behaved subtly differently
 * from every other list on the device.
 */

/** One device, flattened from whichever source it came from. */
interface PeerRow {
  id: string;
  /** The line to show: an alias if the user set one, else the device name, else the id. */
  title: string;
  /** The supporting line: the id, plus the platform when known. */
  subtitle: string;
}

/** One address book, and the devices in it. */
interface PeerGroup {
  name: string;
  peers: PeerRow[];
}

/** The three views, in the order the sub-tabs present them. */
const TAB_ADDRESS_BOOK = 0;
const TAB_FAVOURITES = 1;
const TAB_RECENT = 2;

@Component
export struct AddressBookTab {
  /**
   * Bumped by the page when the account syncs or a peer changes.
   *
   * This tab is built once and kept alive inside its TabContent, so without being told it would
   * keep rendering whatever it read the first time.
   */
  @Prop @Watch('onRevisionChanged') peersRevision: number = 0;

  onConnect: (targetId: string) => void = () => {};

  @State private groups: PeerGroup[] = [];
  @State private favourites: PeerRow[] = [];
  @State private recent: PeerRow[] = [];
  @State private subTab: number = TAB_ADDRESS_BOOK;
  @State private query: string = '';
  @State private signedIn: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  onRevisionChanged(): void {
    this.reload();
  }

  /**
   * Read all three lists.
   *
   * Each source is read in its own guarded step. They are separate calls into the core and any of
   * them can fail on its own, so one failing must not cost the other two -- and the log has to say
   * which one, or a failure here is a blank list with no lead.
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
  }

  /** The rows for whichever sub-tab is showing, filtered by the search box. */
  private visibleGroups(): PeerGroup[] {
    const wanted = this.query.trim().toLowerCase();
    // Built as statements rather than a nested ternary: ArkTS cannot infer a type for an array of
    // object literals, so the shape has to be declared before it is filled.
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
        // Matching the id as well as the title, because a user often has the id in hand rather
        // than the name.
        if (peer.title.toLowerCase().includes(wanted) || peer.id.includes(wanted)) {
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

  build() {
    Column({ space: 12 }) {
      this.buildSubTabs()
      this.buildSearch()

      if (!this.hasAnyPeer() && !this.signedIn) {
        this.buildEmptyState(
          $r('app.string.ab_signed_out'),
          $r('app.string.ab_signed_out_hint')
        )
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
  }

  /** The sub-tabs, using the platform's chip group rather than hand-styled text. */
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
   * `ListItemGroup` is what gives the book headings: without it every device would be one flat
   * run, and a user with several books could not tell which device belongs where.
   */
  @Builder
  private buildList() {
    List({ space: 8 }) {
      ForEach(this.visibleGroups(), (group: PeerGroup) => {
        ListItemGroup({ header: this.buildGroupHeader(group.name) }) {
          ForEach(group.peers, (peer: PeerRow) => {
            ListItem() {
              this.buildRow(peer)
            }
          }, (peer: PeerRow) => peer.id)
        }
      }, (group: PeerGroup) => `${group.name}:${group.peers.length}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildGroupHeader(name: string) {
    // A single-book list does not need a heading saying which book it is; the sub-tab already
    // says that, and a heading above a lone group is noise.
    if (name.length === 0 || this.visibleGroups().length < 2) {
      Row().height(0)
    } else {
      Text(name)
        .fontSize($r('app.float.font_caption'))
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 4, top: 10, bottom: 6 })
    }
  }

  @Builder
  private buildRow(peer: PeerRow) {
    HdsListItemCard({
      textItem: {
        primaryText: { text: peer.title },
        secondaryText: { text: peer.subtitle }
      },
      onClick: () => {
        this.onConnect(peer.id);
      }
    })
      .width('100%')
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

// --- shaping ------------------------------------------------------------------
//
// The three sources have different shapes and the list wants one, so the conversion happens here
// rather than inside the builders -- a builder runs on every frame of a scroll, and reshaping
// there would redo the same work continually.

/**
 * A description of a thrown value.
 *
 * Not JSON.stringify: an Error's message and stack are not enumerable, so stringifying one yields
 * "{}" -- which is exactly how a real failure here was logged as nothing at all.
 */
function messageOf(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  const text = String(e);
  return text.length > 0 ? text : 'unknown error';
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
  const platform = peer.platform ?? '';
  const title = alias.length > 0 ? alias : (hostname.length > 0 ? hostname : id);
  // The platform is worth showing only when it is known; an empty separator would be worse than
  // nothing.
  const subtitle = platform.length > 0 ? `${id} · ${platform}` : id;
  return { id: id, title: title, subtitle: subtitle };
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
    rows.push(found ? rowOf(found) : { id: id, title: id, subtitle: id });
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
    const platform = peer.platform ?? '';
    const title = alias.length > 0 ? alias : (hostname.length > 0 ? hostname : id);
    rows.push({
      id: id,
      title: title,
      subtitle: platform.length > 0 ? `${id} · ${platform}` : id
    });
  }
  return rows;
}
