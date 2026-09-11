/**
 * Typed facade over the RustDesk Node-API bridge.
 *
 * The Rust core (librustdesk.so) plus its N-API wrapper are built by
 * flutter/ohos/build_bridge.ps1 into `librustdesk_ohos.so`, which HarmonyOS loads from
 * entry/src/main/libs/arm64-v8a. That module's members are Rust `#[napi]` functions, so
 * their names and types are fixed on the other side; this file mirrors them once, with
 * types, so pages and components never touch the raw import.
 *
 * Only the functions the bridge currently exports are declared. Keeping the interface
 * exact means a name or arity drift shows up as a compile error here rather than as a
 * failure at runtime on device.
 */

import nativeModule from 'librustdesk_ohos.so';

/** A decoded frame from the core. */
export interface RgbaFrame {
  width: number;
  height: number;
  data: ArrayBuffer;
}

/** The peer's display size, in the peer's own pixels. */
export interface DisplaySize {
  width: number;
  height: number;
}

/** Shape of the module built from flutter/ohos/native/src/lib.rs. */
interface RustDeskNative {
  // --- module identity -------------------------------------------------------
  bridgeVersion(): string;

  // --- core / app identity ---------------------------------------------------
  mainGetVersion(): string;
  mainGetBuildDate(): string;
  mainGetAppName(): string;
  mainGetLicense(): string;

  // --- local device ----------------------------------------------------------
  /** This device's RustDesk ID, i.e. what a peer types to reach it. */
  mainGetMyId(): string;
  mainGetUuid(): string;

  // --- connection state ------------------------------------------------------
  mainIsUsingPublicServer(): boolean;
  mainGetProxyStatus(): boolean;
  mainGetConnectStatus(): string;
  mainGetApiServer(): string;
  mainGetLastRemoteId(): string;

  // --- peers and options -----------------------------------------------------
  /** Serialised JSON: peers discovered on the LAN. */
  mainGetLanPeers(): string;
  /** Serialised JSON: the stored address book. */
  mainGetNewStoredPeers(): string;
  mainGetOptions(): string;
  mainGetOptionsSync(): string;
  mainGetAppNameSync(): string;
  mainUriPrefixSync(): string;
  mainGetLoginDeviceInfo(): string;
  getLocalKbLayoutType(): string;
  mainGetOptionSync(key: string): string;
  mainGetPeerSync(id: string): string;
  mainSetOption(key: string, value: string): void;
  mainSetOptions(json: string): void;
  mainGetLocalOption(key: string): string;
  mainSetLocalOption(key: string, value: string): void;
  mainLoadAb(): string;
  mainSaveAb(json: string): void;
  mainLoadFavPeerIds(): string;
  mainLoadPeers(filter: string): string;
  mainSetPeerAlias(id: string, alias: string): void;
  mainPeerExists(id: string): boolean;
  mainPeerHasPassword(id: string): boolean;
  mainGetPeerOption(id: string, key: string): string;
  mainSetPeerOption(id: string, key: string, value: string): void;
  isDisableAb(): boolean;
  isDisableAccount(): boolean;
  queryOnlines(ids: string[]): void;
  mainSetHomeDir(home: string): void;
  mainDeviceId(id: string): void;
  mainDeviceName(name: string): void;
  mainInit(appDir: string, customClientConfig: string): void;
  mainGetAsyncStatus(): string;
  mainGetError(): string;
  mainGetTemporaryPassword(): string;
  mainUpdateTemporaryPassword(): void;

  sessionAddSync(
    sessionId: string, id: string,
    isFileTransfer: boolean, isViewCamera: boolean, isPortForward: boolean,
    isRdp: boolean, isTerminal: boolean,
    switchUuid: string, forceRelay: boolean,
    password: string, isSharedPassword: boolean
  ): string;
  sessionStart(sessionId: string, id: string): string;
  sessionClose(sessionId: string): void;
  sessionTakeRgba(sessionId: string, display: number): RgbaFrame | undefined;
  sessionReleaseRgba(sessionId: string, display: number): void;
  pollUiEvents(): string;
  videoSurfaceAttach(surfaceId: string): string;
  videoStart(sessionId: string, display: number): string;
  videoStop(): void;
  videoSurfaceDetach(): void;
  videoIsAttached(): boolean;
  sessionGetDisplaySize(sessionId: string, display: number): DisplaySize | undefined;
  sessionSendMouse(sessionId: string, msg: string): void;
  sessionInputKey(
    sessionId: string, name: string,
    down: boolean, press: boolean,
    alt: boolean, ctrl: boolean, shift: boolean, command: boolean
  ): void;
  sessionInputString(sessionId: string, value: string): void;
  clipboardTakePending(): string;
  clipboardSend(text: string): string;
  sessionAddFileTransfer(sessionId: string, id: string, password: string): string;
  sessionSendFiles(sessionId: string, actId: number, path: string, to: string,
                   fileNum: number, includeHidden: boolean, isRemote: boolean): void;
  sessionReadRemoteDir(sessionId: string, path: string, includeHidden: boolean): void;
  sessionReadLocalDirSync(sessionId: string, path: string, showHidden: boolean): string;
  sessionCreateDir(sessionId: string, actId: number, path: string, isRemote: boolean): void;
  sessionRemoveFile(sessionId: string, actId: number, path: string, fileNum: number, isRemote: boolean): void;
  sessionRemoveDirAll(sessionId: string, actId: number, path: string, isRemote: boolean, showHidden: boolean): void;
  sessionRenameFile(sessionId: string, actId: number, path: string, newName: string, isRemote: boolean): void;
  sessionSetConfirmOverrideFile(sessionId: string, actId: number, fileNum: number,
                                needOverride: boolean, remember: boolean, isUpload: boolean): void;

  // --- rendering -------------------------------------------------------------
  /** Next texture key to register an XComponent surface under. */
  getNextTextureKey(): number;

  // --- sessions --------------------------------------------------------------
  peerGetSessionsCount(id: string, connType: number): number;
  sessionIsMultiUiSession(sessionId: string): boolean;
  sessionGetIsRecording(sessionId: string): boolean;
  sessionGetEnableTrustedDevices(sessionId: string): boolean;
  willSessionCloseCloseSession(sessionId: string): boolean;
  sessionIsKeyboardModeSupported(sessionId: string, mode: string): boolean;
  sessionGetToggleOptionSync(sessionId: string, arg: string): boolean;
  sessionGetReverseMouseWheelSync(sessionId: string): string;
}

const native: RustDeskNative = nativeModule as RustDeskNative;

/**
 * Read this device's RustDesk ID.
 *
 * Returns an empty string if the core has no ID yet, which is the case before the core is
 * initialised. Callers should treat that as "not ready" rather than as an error.
 */
export function getMyId(): string {
  return native.mainGetMyId();
}

/**
 * This device's hardware uuid.
 *
 * What the account server uses to tell one device from another, and what the sign-in request
 * carries. Read from the core rather than generated, so the server keeps a single view of this
 * device instead of seeing a new one on every launch.
 */
export function getUuid(): string {
  return native.mainGetUuid();
}

/** The core's version, e.g. for an about panel. */
export function getCoreVersion(): string {
  return native.mainGetVersion();
}

/** The bridge's own version, for confirming which .so a device is running. */
export function getBridgeVersion(): string {
  return native.bridgeVersion();
}

/** Build date of the linked core. */
export function getCoreBuildDate(): string {
  return native.mainGetBuildDate();
}

/** Product name as the core reports it. */
export function getAppName(): string {
  return native.mainGetAppName();
}

/** Whether the session is routed through the public rendezvous/relay servers. */
export function isUsingPublicServer(): boolean {
  return native.mainIsUsingPublicServer();
}

/** Serialised connection status. */
export function getConnectStatus(): string {
  return native.mainGetConnectStatus();
}

/** The configured API server. */
export function getApiServer(): string {
  return native.mainGetApiServer();
}

/** The last remote ID this device connected to. */
export function getLastRemoteId(): string {
  return native.mainGetLastRemoteId();
}

/** Serialised address book of stored peers. */
export function getStoredPeers(): string {
  return native.mainGetNewStoredPeers();
}

/** Serialised list of peers discovered on the LAN. */
export function getLanPeers(): string {
  return native.mainGetLanPeers();
}

/**
 * Peers discovered on the local network, parsed.
 *
 * Discovery is the core's: it listens for RustDesk's LAN announcements. The list is read from the
 * core's store rather than held here, so it reflects what the core currently knows rather than a
 * snapshot taken when the page was built.
 */
export interface LanPeer {
  id: string;
  username: string;
  hostname: string;
  platform: string;
}

export function getLanPeerList(): LanPeer[] {
  const raw = native.mainGetLanPeers();
  if (!raw || raw.length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as LanPeer[];
    return parsed ? parsed : [];
  } catch (e) {
    return [];
  }
}

/**
 * Read one core option by key.
 *
 * The key vocabulary is the core's, e.g. `custom-rendezvous-server`, `relay-server`,
 * `api-server`, `key`. See libs/base/src/config/keys.rs for the authoritative list.
 */
export function getOption(key: string): string {
  return native.mainGetOptionSync(key);
}

/**
 * Write one core option.
 *
 * Deliberately the only option writer exposed. The bridge also has a bulk call, which assigns
 * the core's entire option map rather than merging and skips the per-key side effects below --
 * using it once would silently drop any option set elsewhere. Callers set one key at a time.
 *
 * Keys are the core's own option names (libs/base/src/config/keys.rs). An empty value clears
 * the option, which is how the core returns to its built-in default.
 */
export function setOption(key: string, value: string): void {
  native.mainSetOption(key, value);
}

// --- local options ------------------------------------------------------------

/** Read a local option: this device's own settings, not the synchronised configuration. */
export function getLocalOption(key: string): string {
  return native.mainGetLocalOption(key);
}

/** Set a local option. */
export function setLocalOption(key: string, value: string): void {
  native.mainSetLocalOption(key, value);
}

/**
 * The account token's key in the local options.
 *
 * Named here rather than repeated as a literal: the core and the desktop client look for the
 * token under this exact key when they build an authenticated request, and a typo would look like
 * "the account is signed in but every request is unauthorised".
 */
export const LOCAL_OPTION_ACCESS_TOKEN = 'access_token';

// --- address book -------------------------------------------------------------

/**
 * One entry in the account's address book.
 *
 * Every field is optional, and that is not defensive typing: the core serialises these structures
 * with `skip_serializing_if = "String::is_empty"`, so an empty field is *absent* from the JSON it
 * returns rather than present and empty. Declaring them as required would be a lie the compiler
 * believes and the runtime does not -- reading `.length` on one that happens to be empty is a
 * thrown exception, which is how this was found.
 */
export interface AbPeer {
  id?: string;
  username?: string;
  hostname?: string;
  alias?: string;
  platform?: string;
  tags?: string[];
  /** The stored peer password, which the account keeps so a connect need not ask for it. */
  password?: string;
  /** The peer's public key hash, used to pin the connection. */
  hash?: string;
  loginName?: string;
  forceAlwaysRelay?: boolean;
  /** Whether this peer is favourited, as the core stores it. */
  favorite?: boolean;
}

/** A stored peer as the core reports it. Omitted-when-empty, as above. */
export interface StoredPeerInfo {
  id?: string;
  username?: string;
  hostname?: string;
  alias?: string;
  platform?: string;
}

/** The address book as the core holds it. Omitted-when-empty, as above. */
export interface AddressBook {
  access_token?: string;
  ab_entries?: AbEntry[];
}

export interface AbEntry {
  guid?: string;
  name?: string;
  tags?: string[];
  peers?: AbPeer[];
}

/**
 * The address book the core has stored.
 *
 * This is the account's book once it has been synced -- see {@link saveAddressBook}. Empty
 * entries mean nothing has been synced yet, which is what a fresh install looks like.
 */
export function loadAddressBook(): AddressBook {
  const raw = native.mainLoadAb();
  if (!raw || raw.length === 0) {
    return { access_token: '', ab_entries: [] };
  }
  try {
    const parsed = JSON.parse(raw) as AddressBook;
    if (!parsed.ab_entries) {
      parsed.ab_entries = [];
    }
    return parsed;
  } catch (e) {
    return { access_token: '', ab_entries: [] };
  }
}

/**
 * Store the address book in the core.
 *
 * The front end fetches it over HTTP, because it holds the login and knows the API server; the
 * core keeps it so aliases, tags and remembered passwords survive a restart. The desktop client
 * does the same thing through the same call.
 */
export function saveAddressBook(book: AddressBook): void {
  native.mainSaveAb(JSON.stringify(book));
}

/** Favourite peer ids. */
export function loadFavouritePeerIds(): string[] {
  const raw = native.mainLoadFavPeerIds();
  if (!raw || raw.length === 0) {
    return [];
  }
  try {
    return JSON.parse(raw) as string[];
  } catch (e) {
    return [];
  }
}

/**
 * Stored peers with their details.
 *
 * `ids` restricts the result; pass an empty array for all of them. Favourites are this same call
 * with the favourite ids rather than a separate path.
 */
export function loadStoredPeers(ids: string[]): StoredPeerInfo[] {
  const raw = native.mainLoadPeers(JSON.stringify(ids));
  if (!raw || raw.length === 0) {
    return [];
  }
  try {
    return JSON.parse(raw) as StoredPeerInfo[];
  } catch (e) {
    return [];
  }
}

/** Set the local name for a peer. */
export function setPeerAlias(id: string, alias: string): void {
  native.mainSetPeerAlias(id, alias);
}

/** Whether a peer is known to the core at all. */
export function peerExists(id: string): boolean {
  return native.mainPeerExists(id);
}

/** Whether a password is stored for a peer, so the UI can skip asking for one. */
export function peerHasPassword(id: string): boolean {
  return native.mainPeerHasPassword(id);
}

/** A per-peer option. */
export function getPeerOption(id: string, key: string): string {
  return native.mainGetPeerOption(id, key);
}

/** Set a per-peer option. */
export function setPeerOption(id: string, key: string, value: string): void {
  native.mainSetPeerOption(id, key, value);
}
/**
 * Ask the server which of these peers are online.
 *
 * Nothing comes back from this call: it is a query against the rendezvous server, so the answer
 * arrives as an event on the queue {@link pollUiEvents} drains, named `callback_query_onlines`
 * with `onlines` and `offlines` as comma-separated id lists. The Flutter client receives the same
 * payload through its global event stream.
 */
export function queryOnlines(ids: string[]): void {
  native.queryOnlines(ids);
}

/**
 * Start the core.
 *
 * Must run once, before any other bridge call, or the core has no directory to write to and
 * nothing it stores survives the process: the device id is regenerated on every launch and
 * saved options are not found again. The order within is the one the Flutter client uses --
 * directories and identity first, then init.
 *
 * @param appDir the application's own data directory, from the ability context.
 * @param deviceName a display name; shown as this device's name to peers.
 */
export function initCore(appDir: string, deviceName: string): void {
  native.mainSetHomeDir(appDir);
  // DEVICE_ID is written but not read anywhere in the core today; an empty value leaves it at
  // its default, and the real id comes from the core's own generated id. Passed for parity
  // with the Flutter init sequence in case that changes.
  native.mainDeviceId('');
  native.mainDeviceName(deviceName);
  native.mainInit(appDir, '');
}

/** The core's asynchronous job status, polled while starting up. */
export function getAsyncStatus(): string {
  return native.mainGetAsyncStatus();
}

/** The last error the core recorded, empty when there is none. */
export function getLastError(): string {
  return native.mainGetError();
}

/** This device's one-time password. Empty until the core has generated one. */
export function getTemporaryPassword(): string {
  return native.mainGetTemporaryPassword();
}

/** Invalidate the current one-time password and generate a new one. */
export function updateTemporaryPassword(): void {
  native.mainUpdateTemporaryPassword();
}

// --- sessions and video -------------------------------------------------------

/** What went wrong, or empty on success. The core reports failures as strings. */
export type CoreResult = string;

/**
 * Register a session with the core.
 *
 * `password` authorises the connection; `isSharedPassword` says it is the peer's one-time
 * password rather than its permanent one.
 */
export function sessionAdd(sessionId: string, id: string,
                           password: string, isSharedPassword: boolean): CoreResult {
  return native.sessionAddSync(
    sessionId, id,
    false, false, false, false, false,
    '', false,
    password, isSharedPassword
  );
}

/** Start connecting. Returns what went wrong, or empty on success. */
export function sessionStart(sessionId: string, id: string): CoreResult {
  return native.sessionStart(sessionId, id);
}

/** Close the session and release it, so the same id can be used again. */
export function sessionClose(sessionId: string): void {
  native.sessionClose(sessionId);
}

/** Drain the core's UI events. They carry status only; the picture comes from the surface. */
export function pollUiEvents(): string[] {
  const raw = native.pollUiEvents();
  if (!raw || raw.length === 0) {
    return [];
  }
  try {
    return JSON.parse(raw) as string[];
  } catch (e) {
    return [];
  }
}

/**
 * Bind the surface an XComponent created and start drawing into it.
 *
 * Returns what went wrong, or empty on success. Frames do not come back through ArkTS -- the
 * core writes them straight into the surface -- so this is the whole per-session video setup.
 */
export function videoAttachAndStart(surfaceId: string, sessionId: string, display: number): CoreResult {
  const err = native.videoSurfaceAttach(surfaceId);
  if (err.length > 0) {
    return err;
  }
  return native.videoStart(sessionId, display);
}

/** Stop drawing and release the surface. */
export function videoDetach(): void {
  native.videoSurfaceDetach();
}

// --- input --------------------------------------------------------------------

/** The peer's display size, or undefined until the peer announces it. */
export function getDisplaySize(sessionId: string, display: number): DisplaySize | undefined {
  return native.sessionGetDisplaySize(sessionId, display);
}

/** Send a mouse message in the core's own JSON shape. Prefer RemoteInput, which builds them. */
export function sendMouse(sessionId: string, msg: string): void {
  native.sessionSendMouse(sessionId, msg);
}

/** Send a key event by the core's key name. */
export function inputKey(sessionId: string, name: string, down: boolean, press: boolean,
                         alt: boolean, ctrl: boolean, shift: boolean, command: boolean): void {
  native.sessionInputKey(sessionId, name, down, press, alt, ctrl, shift, command);
}

/** Send a run of typed text, which does not depend on the peer's keyboard layout. */
export function inputString(sessionId: string, value: string): void {
  native.sessionInputString(sessionId, value);
}

// --- clipboard ----------------------------------------------------------------

/**
 * Take clipboard text the peer has sent, or an empty string when there is nothing new.
 *
 * Taken rather than read: the caller writes it to the pasteboard, and getting the same value
 * again would keep re-applying a clipboard the user may since have replaced.
 */
export function clipboardTakePending(): string {
  return native.clipboardTakePending();
}

/**
 * Send this device's clipboard text to the peer.
 *
 * Empty string on success. The usual failure is having no session, which is not worth showing.
 */
export function clipboardSend(text: string): string {
  return native.clipboardSend(text);
}

/** Whether the given session is currently being recorded. */
export function isSessionRecording(sessionId: string): boolean {
  return native.sessionGetIsRecording(sessionId);
}

/**
 * How many live sessions a peer has.
 *
 * `connType` is the core's own connection-type code; 0 covers the ordinary remote-desktop
 * case, which is the only one the UI asks about today.
 */
export function peerGetSessionsCount(id: string, connType: number): number {
  return native.peerGetSessionsCount(id, connType);
}

/** Next texture key for registering an XComponent surface. */
export function getNextTextureKey(): number {
  return native.getNextTextureKey();
}
