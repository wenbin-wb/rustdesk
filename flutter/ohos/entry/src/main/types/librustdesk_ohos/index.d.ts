/**
 * Type declaration for the RustDesk Node-API module.
 *
 * HarmonyOS requires a module's shape to be declared before ArkTS can import the native
 * library; without this file hvigor warns that the module "is not verified" and the default
 * import resolves to undefined at runtime. Names and arities here must match the Rust
 * `#[napi]` members in flutter/ohos/native/src/lib.rs -- a mismatch is a compile error in
 * ArkTS, which is the point.
 */

export const bridgeVersion: () => string;

// Core / app identity
export const mainGetVersion: () => string;
export const mainGetBuildDate: () => string;
export const mainGetAppName: () => string;
export const mainGetLicense: () => string;

// Local device
export const mainGetMyId: () => string;
export const mainGetUuid: () => string;

// Connection state
export const mainIsUsingPublicServer: () => boolean;
export const mainGetProxyStatus: () => boolean;
export const mainGetConnectStatus: () => string;
export const mainGetApiServer: () => string;
export const mainGetLastRemoteId: () => string;

// Peers and options
export const mainGetLanPeers: () => string;
export const mainGetNewStoredPeers: () => string;
export const mainGetOptions: () => string;
export const mainGetOptionsSync: () => string;
export const mainGetAppNameSync: () => string;
export const mainUriPrefixSync: () => string;
export const mainGetLoginDeviceInfo: () => string;
export const getLocalKbLayoutType: () => string;
export const mainGetOptionSync: (key: string) => string;
export const mainGetPeerSync: (id: string) => string;

// Writing options. Without these the UI could read the core's configuration but never
// change it, so a self-hosted server set in the app would never reach the core.
export const mainSetOption: (key: string, value: string) => void;
export const mainSetOptions: (json: string) => void;

// Local options: this device's own settings, separate from the synchronised configuration. The
// account token lives here, which is where the core looks for it when building an authenticated
// request.
export const mainGetLocalOption: (key: string) => string;
export const mainSetLocalOption: (key: string, value: string) => void;

// Address book, favourites and per-peer data. Read from the core because the core is what the
// account syncs into and where an alias or a remembered password lives.
export const mainLoadAb: () => string;
export const mainSaveAb: (json: string) => void;
/** Favourite peer ids, as a JSON array. */
export const mainLoadFavPeerIds: () => string;
/** Stored peers with details; `filter` is a JSON array of ids, or empty for all. */
export const mainLoadPeers: (filter: string) => string;
export const mainSetPeerAlias: (id: string, alias: string) => void;
export const mainPeerExists: (id: string) => boolean;
export const mainPeerHasPassword: (id: string) => boolean;
export const mainGetPeerOption: (id: string, key: string) => string;
export const mainSetPeerOption: (id: string, key: string, value: string) => void;
export const isDisableAb: () => boolean;
export const isDisableAccount: () => boolean;

// Core lifecycle. Must run before any other call: until it does, the core has no directory
// to write to, so the device id is regenerated each launch and nothing is persisted.
export const mainSetHomeDir: (home: string) => void;
export const mainDeviceId: (id: string) => void;
export const mainDeviceName: (name: string) => void;
export const mainInit: (appDir: string, customClientConfig: string) => void;
export const mainGetAsyncStatus: () => string;
export const mainGetError: () => string;
export const mainGetTemporaryPassword: () => string;
export const mainUpdateTemporaryPassword: () => void;

// Sessions and video. Session ids are UUID strings; ArkTS generates one per connect.
//
// sessionTakeRgba returns a copy of the frame the core has decoded for a display, or undefined
// when none is waiting. sessionReleaseRgba must be called once it has been consumed, or the
// core will not decode the next one -- that handshake is what paces the stream.
export interface RgbaFrame {
  width: number;
  height: number;
  data: ArrayBuffer;
}

export const sessionAddSync: (
  sessionId: string, id: string,
  isFileTransfer: boolean, isViewCamera: boolean, isPortForward: boolean,
  isRdp: boolean, isTerminal: boolean,
  switchUuid: string, forceRelay: boolean,
  password: string, isSharedPassword: boolean
) => string;
export const sessionStart: (sessionId: string, id: string) => string;
export const sessionClose: (sessionId: string) => void;
export const sessionTakeRgba: (sessionId: string, display: number) => RgbaFrame | undefined;
export const sessionReleaseRgba: (sessionId: string, display: number) => void;
export const pollUiEvents: () => string;

// Video surface. The XComponent hands out a surface and Rust writes frames into it directly, so
// no frame crosses this boundary -- which is why there is no per-frame call here.
export const videoSurfaceAttach: (surfaceId: string) => string;
export const videoStart: (sessionId: string, display: number) => string;
export const videoStop: () => void;
export const videoSurfaceDetach: () => void;
export const videoIsAttached: () => boolean;

// Input. Positions are in the peer's coordinate space, which is why the display size is exposed
// first: a touch on the surface has to be scaled by displaySize / surfaceSize before it is sent.
export interface DisplaySize {
  width: number;
  height: number;
}

export const sessionGetDisplaySize: (sessionId: string, display: number) => DisplaySize | undefined;
export const sessionSendMouse: (sessionId: string, msg: string) => void;
export const sessionInputKey: (
  sessionId: string, name: string,
  down: boolean, press: boolean,
  alt: boolean, ctrl: boolean, shift: boolean, command: boolean
) => void;
export const sessionInputString: (sessionId: string, value: string) => void;

// Clipboard. ArkTS owns the system pasteboard, so text crosses in both directions instead of the
// core applying it -- the core's clipboard module is excluded for HarmonyOS, as for iOS.
export const clipboardTakePending: () => string;
export const clipboardSend: (text: string) => string;

// File transfer. A transfer is its own session kind, registered with sessionAddFileTransfer;
// operations after that are per-request, keyed by an actId the caller allocates, and the core
// answers with events on the UI queue rather than by returning from these calls.
export const sessionAddFileTransfer: (sessionId: string, id: string, password: string) => string;
export const sessionSendFiles: (
  sessionId: string, actId: number, path: string, to: string,
  fileNum: number, includeHidden: boolean, isRemote: boolean
) => void;
export const sessionReadRemoteDir: (sessionId: string, path: string, includeHidden: boolean) => void;
/** Local listing returns synchronously; there is no round trip to wait for. */
export const sessionReadLocalDirSync: (sessionId: string, path: string, showHidden: boolean) => string;
export const sessionCreateDir: (sessionId: string, actId: number, path: string, isRemote: boolean) => void;
export const sessionRemoveFile: (
  sessionId: string, actId: number, path: string, fileNum: number, isRemote: boolean
) => void;
/** Scans the directory first and reports; the removal follows once the caller confirms. */
export const sessionRemoveDirAll: (
  sessionId: string, actId: number, path: string, isRemote: boolean, showHidden: boolean
) => void;
export const sessionRenameFile: (
  sessionId: string, actId: number, path: string, newName: string, isRemote: boolean
) => void;
export const sessionSetConfirmOverrideFile: (
  sessionId: string, actId: number, fileNum: number,
  needOverride: boolean, remember: boolean, isUpload: boolean
) => void;

// Rendering
export const getNextTextureKey: () => number;

// Sessions
export const peerGetSessionsCount: (id: string, connType: number) => number;
export const sessionIsMultiUiSession: (sessionId: string) => boolean;
export const sessionGetIsRecording: (sessionId: string) => boolean;
export const sessionGetEnableTrustedDevices: (sessionId: string) => boolean;
export const willSessionCloseCloseSession: (sessionId: string) => boolean;
export const sessionIsKeyboardModeSupported: (sessionId: string, mode: string) => boolean;
export const sessionGetToggleOptionSync: (sessionId: string, arg: string) => boolean;
export const sessionGetReverseMouseWheelSync: (sessionId: string) => string;
