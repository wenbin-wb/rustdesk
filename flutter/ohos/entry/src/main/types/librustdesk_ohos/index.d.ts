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
