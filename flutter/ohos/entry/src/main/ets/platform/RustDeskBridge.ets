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
 * Read one core option by key.
 *
 * The key vocabulary is the core's, e.g. `custom-rendezvous-server`, `relay-server`,
 * `api-server`, `key`. See libs/base/src/config/keys.rs for the authoritative list.
 */
export function getOption(key: string): string {
  return native.mainGetOptionSync(key);
}

/**
 * Write several core options at once.
 *
 * Keys are the core's own option names (libs/base/src/config/keys.rs), not the UI's. An
 * empty value clears the option, which is how the core returns to its built-in default --
 * for the server options, the public servers.
 */
export function setOptions(options: Record<string, string>): void {
  native.mainSetOptions(JSON.stringify(options));
}

/** Write one core option. */
export function setOption(key: string, value: string): void {
  native.mainSetOption(key, value);
}

/** Whether the given session is currently being recorded. */
export function isSessionRecording(sessionId: string): boolean {
  return native.sessionGetIsRecording(sessionId);
}

/** Next texture key for registering an XComponent surface. */
export function getNextTextureKey(): number {
  return native.getNextTextureKey();
}
