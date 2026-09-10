//! Node-API bridge between the RustDesk core and ArkTS on HarmonyOS.
//!
//! HarmonyOS has no Dart isolate, so the Flutter-facing bridge in the core crate
//! (`src/flutter_ffi.rs`, built against flutter_rust_bridge) cannot be called from ArkTS.
//! Instead the core is linked into this cdylib and re-exported as N-API members, which
//! ArkTS imports directly:
//!
//! ```ts
//! import bridge from 'librustdesk_ohos.so';
//! bridge.bridgeVersion();
//! bridge.mainGetVersion();
//! bridge.mainGetMyId();
//! ```
//!
//! ### How exports are wrapped
//!
//! Only exports taking and returning plain N-API-compatible types are wrapped here; for
//! those, the `passthrough!` macro keeps each one a single line and makes it obvious at a
//! glance which core functions have been surfaced. The rest of `flutter_ffi` needs a
//! deliberate shape decision rather than a mechanical rewrite:
//!
//! - functions returning `SyncReturn<T>`: the value has to be unwrapped, not passed
//!   through. `SyncReturn` is a flutter_rust_bridge type meaning "return this
//!   synchronously instead of as a Future"; N-API has no such wrapper.
//! - functions taking `StreamSink`: these are event channels, which ohos replaces with
//!   its own delivery path rather than a NAPI callback argument.
//! - functions taking `SessionID` as a UUID string: these need a decision on how ArkTS
//!   identifies a session.
//!
//! See flutter/ohos/PLAN.md for the P2 breakdown.

#[macro_use]
extern crate napi_derive_ohos;

/// Surface core functions through the bridge unchanged.
///
/// The core's exports keep their `flutter_ffi` names, and the `js_name` attribute maps
/// them to the lowerCamelCase ArkTS expects.
macro_rules! passthrough_string {
    ($( $rust_name:ident => $js_name:literal ),* $(,)?) => {
        $(
            #[napi(js_name = $js_name)]
            pub fn $rust_name() -> String {
                librustdesk::flutter_ffi::$rust_name()
            }
        )*
    };
}

/// Identity of the bridge itself, for smoke-testing that the module loaded and that
/// ArkTS can call across the boundary.
#[napi]
pub fn bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

// --- the core's version -------------------------------------------------------

/// The core's version. Confirms the core is linked in and callable, not merely present
/// in the dependency graph.
#[napi(js_name = "mainGetVersion")]
pub fn main_get_version() -> String {
    librustdesk::flutter_ffi::main_get_version()
}

/// Build date of the linked core, useful for confirming which artifact a device runs.
#[napi(js_name = "mainGetBuildDate")]
pub fn main_get_build_date() -> String {
    librustdesk::flutter_ffi::main_get_build_date()
}

// --- local device -------------------------------------------------------------

/// The local device's RustDesk ID -- the value a peer types to reach this device.
#[napi(js_name = "mainGetMyId")]
pub fn main_get_my_id() -> String {
    librustdesk::flutter_ffi::main_get_my_id()
}

/// The local device's machine UUID, which the ID derives from.
#[napi(js_name = "mainGetUuid")]
pub fn main_get_uuid() -> String {
    librustdesk::flutter_ffi::main_get_uuid()
}

// --- booleans the UI polls ----------------------------------------------------

/// Whether the session is going through the public rendezvous/relay servers.
#[napi(js_name = "mainIsUsingPublicServer")]
pub fn main_is_using_public_server() -> bool {
    librustdesk::flutter_ffi::main_is_using_public_server()
}

/// Whether a proxy is currently in use.
#[napi(js_name = "mainGetProxyStatus")]
pub fn main_get_proxy_status() -> bool {
    librustdesk::flutter_ffi::main_get_proxy_status()
}

// --- strings the UI polls -----------------------------------------------------

passthrough_string! {
    main_get_app_name        => "mainGetAppName",
    main_get_license         => "mainGetLicense",
    main_get_connect_status  => "mainGetConnectStatus",
    main_get_api_server      => "mainGetApiServer",
    main_get_last_remote_id  => "mainGetLastRemoteId",
    main_get_lan_peers       => "mainGetLanPeers",
    main_get_new_stored_peers => "mainGetNewStoredPeers",
    main_get_options         => "mainGetOptions",
}

// --- SyncReturn family --------------------------------------------------------
//
// These core exports return `SyncReturn<T>`, which is flutter_rust_bridge's marker for
// "hand this back synchronously rather than as a Future" -- it carries no data of its
// own, it is a `SyncReturn<T>(pub T)` newtype. N-API has no equivalent concept: a NAPI
// function returning a plain value is already synchronous. So the bridge unwraps with
// `.0` and exposes the bare payload.
//
// Each macro below adds one parameter, because writing `$arg:ident` handling inline is
// less clear than naming the arities actually in use.

/// `fn() -> SyncReturn<String>`
macro_rules! sync_string_0 {
    ($( $rust_name:ident => $js_name:literal ),* $(,)?) => {
        $(
            #[napi(js_name = $js_name)]
            pub fn $rust_name() -> String {
                librustdesk::flutter_ffi::$rust_name().0
            }
        )*
    };
}

/// `fn(String) -> SyncReturn<String>`
macro_rules! sync_string_1 {
    ($( $rust_name:ident => $js_name:literal ),* $(,)?) => {
        $(
            #[napi(js_name = $js_name)]
            pub fn $rust_name(arg: String) -> String {
                librustdesk::flutter_ffi::$rust_name(arg).0
            }
        )*
    };
}

/// Options and identity reads that the Flutter side takes synchronously.
sync_string_0! {
    main_get_options_sync     => "mainGetOptionsSync",
    main_get_app_name_sync    => "mainGetAppNameSync",
    main_uri_prefix_sync      => "mainUriPrefixSync",
    main_get_login_device_info => "mainGetLoginDeviceInfo",
    get_local_kb_layout_type  => "getLocalKbLayoutType",
}

/// ...and the same reads keyed by an argument.
sync_string_1! {
    main_get_option_sync => "mainGetOptionSync",
    main_get_peer_sync   => "mainGetPeerSync",
}

/// The next texture key the renderer wants to register an XComponent surface under.
/// Plain i32, so it needs no unwrapping helper beyond `.0`.
#[napi(js_name = "getNextTextureKey")]
pub fn get_next_texture_key() -> i32 {
    librustdesk::flutter_ffi::get_next_texture_key().0
}

/// How many live sessions a peer has. `usize` maps to a NAPI number.
#[napi(js_name = "peerGetSessionsCount")]
pub fn peer_get_sessions_count(id: String, conn_type: i32) -> u32 {
    librustdesk::flutter_ffi::peer_get_sessions_count(id, conn_type).0 as u32
}

// --- session family -----------------------------------------------------------
//
// The core identifies a session by `SessionID`, which is `uuid::Uuid`. ArkTS has no
// equivalent type, so the agreed representation is the canonical hyphenated UUID string
// -- the same value the Flutter side carries, which keeps logs and any cross-referencing
// identical between the two front ends.
//
// A malformed id is a programming error on the caller's side, not a recoverable state, but
// panicking across the N-API boundary would abort the app. So parsing failures are turned
// into the same value the core uses for "this session does not exist": the functions below
// all look the id up and return their negative result when nothing matches.

/// Parse the ArkTS-facing session id, or `None` if it is not a UUID.
fn parse_session(id: &str) -> Option<uuid::Uuid> {
    uuid::Uuid::parse_str(id).ok()
}

/// Whether the session spans more than one UI window.
#[napi(js_name = "sessionIsMultiUiSession")]
pub fn session_is_multi_ui_session(session_id: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_is_multi_ui_session(id).0,
        None => false,
    }
}

/// Whether the session is currently being recorded.
#[napi(js_name = "sessionGetIsRecording")]
pub fn session_get_is_recording(session_id: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_get_is_recording(id).0,
        None => false,
    }
}

/// Whether the peer allows trusted devices for this session.
#[napi(js_name = "sessionGetEnableTrustedDevices")]
pub fn session_get_enable_trusted_devices(session_id: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_get_enable_trusted_devices(id).0,
        None => false,
    }
}

/// Whether closing the window will also close the session.
#[napi(js_name = "willSessionCloseCloseSession")]
pub fn will_session_close_close_session(session_id: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::will_session_close_close_session(id).0,
        None => false,
    }
}

/// Whether the peer supports the given keyboard mode.
#[napi(js_name = "sessionIsKeyboardModeSupported")]
pub fn session_is_keyboard_mode_supported(session_id: String, mode: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_is_keyboard_mode_supported(id, mode).0,
        None => false,
    }
}

/// Read a boolean session toggle by name.
#[napi(js_name = "sessionGetToggleOptionSync")]
pub fn session_get_toggle_option_sync(session_id: String, arg: String) -> bool {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_get_toggle_option_sync(id, arg).0,
        None => false,
    }
}

/// The session's reverse-mouse-wheel setting, empty when unset or unknown.
#[napi(js_name = "sessionGetReverseMouseWheelSync")]
pub fn session_get_reverse_mouse_wheel_sync(session_id: String) -> String {
    match parse_session(&session_id) {
        Some(id) => librustdesk::flutter_ffi::session_get_reverse_mouse_wheel_sync(id)
            .0
            .unwrap_or_default(),
        None => String::new(),
    }
}

// --- writing options ----------------------------------------------------------
//
// Without these the app could read the core's configuration but never change it, so
// anything the UI collected -- a self-hosted server above all -- stayed in the ArkTS store
// and never reached the component that actually opens connections.

/// Set one core option, by the core's own key name.
///
/// Keys are the ones in libs/base/src/config/keys.rs, e.g. `custom-rendezvous-server`,
/// `relay-server`, `api-server`, `key`.
#[napi(js_name = "mainSetOption")]
pub fn main_set_option(key: String, value: String) {
    librustdesk::flutter_ffi::main_set_option(key, value)
}

/// Set several core options at once, from a JSON object of key to value.
#[napi(js_name = "mainSetOptions")]
pub fn main_set_options(json: String) {
    librustdesk::flutter_ffi::main_set_options(json)
}

// --- core lifecycle -----------------------------------------------------------
//
// The core has to be told who it is and where it may write before anything else works. Until
// this sequence runs, Config::path() resolves against a directory that was never set, so the
// device id is regenerated on every launch and no option or peer is ever persisted -- the
// settings UI writes values that the next process cannot find. The order below is the one the
// Flutter side uses (flutter/lib/models/native_model.dart): identity and directories first,
// then init.

/// Directory the core may write its configuration and data to.
#[napi(js_name = "mainSetHomeDir")]
pub fn main_set_home_dir(home: String) {
    librustdesk::flutter_ffi::main_set_home_dir(home)
}

/// This device's id, as decided by the host application before the core starts.
#[napi(js_name = "mainDeviceId")]
pub fn main_device_id(id: String) {
    librustdesk::flutter_ffi::main_device_id(id)
}

/// This device's display name.
#[napi(js_name = "mainDeviceName")]
pub fn main_device_name(name: String) {
    librustdesk::flutter_ffi::main_device_name(name)
}

/// Start the core.
///
/// `app_dir` is the application's data directory; it becomes the base for every path the core
/// resolves, and `custom_client_config` is left empty for the built-in client configuration.
/// Call this after the setters above and before any other API.
#[napi(js_name = "mainInit")]
pub fn main_init(app_dir: String, custom_client_config: String) {
    librustdesk::flutter_ffi::main_init(app_dir, custom_client_config)
}

/// The core's asynchronous job status, which the UI polls while starting up.
#[napi(js_name = "mainGetAsyncStatus")]
pub fn main_get_async_status() -> String {
    librustdesk::flutter_ffi::main_get_async_status()
}

/// The last error the core recorded, empty when there is none.
#[napi(js_name = "mainGetError")]
pub fn main_get_error() -> String {
    librustdesk::flutter_ffi::main_get_error()
}
