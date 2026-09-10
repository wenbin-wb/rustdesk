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
  mainSetHomeDir(home: string): void;
  mainDeviceId(id: string): void;
  mainDeviceName(name: string): void;
  mainInit(appDir: string, customClientConfig: string): void;
  mainGetAsyncStatus(): string;
  mainGetError(): string;

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
