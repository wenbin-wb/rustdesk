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

use napi_ohos::bindgen_prelude::Buffer;

mod surface;

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

/// This device's one-time password: the short code a peer may use instead of the permanent one.
///
/// Read from the core rather than kept by the app, because the core is what generates and
/// rotates it. The UI previously read a preferences key that nothing ever wrote, so the field
/// could only ever show a placeholder.
#[napi(js_name = "mainGetTemporaryPassword")]
pub fn main_get_temporary_password() -> String {
    librustdesk::flutter_ffi::main_get_temporary_password()
}

/// Rotate the one-time password, invalidating the previous one.
#[napi(js_name = "mainUpdateTemporaryPassword")]
pub fn main_update_temporary_password() {
    librustdesk::flutter_ffi::main_update_temporary_password()
}

// --- sessions and video -------------------------------------------------------
//
// The connection and its picture. Session ids are UUID strings, as everywhere else in this
// bridge; ArkTS generates one per connect and uses it for every later call.

/// Register a session for `id`. Empty string on success, otherwise the failure message.
///
/// `password` is the peer's password and `isSharedPassword` marks it as the peer's one-time
/// password rather than its permanent one. The remaining flags select the kind of session; the
/// ordinary remote-desktop case leaves them all false.
#[napi(js_name = "sessionAddSync")]
pub fn session_add_sync(
    session_id: String,
    id: String,
    is_file_transfer: bool,
    is_view_camera: bool,
    is_port_forward: bool,
    is_rdp: bool,
    is_terminal: bool,
    switch_uuid: String,
    force_relay: bool,
    password: String,
    is_shared_password: bool,
) -> String {
    let Some(session_id) = parse_session(&session_id) else {
        return "invalid session id".to_owned();
    };
    // conn_token is optional and unused by the mobile clients.
    librustdesk::flutter_ffi::session_add_sync(
        session_id,
        id,
        is_file_transfer,
        is_view_camera,
        is_port_forward,
        is_rdp,
        is_terminal,
        switch_uuid,
        force_relay,
        password,
        is_shared_password,
        None,
    )
    .0
}

/// Start connecting. Empty string on success, otherwise the failure message.
#[napi(js_name = "sessionStart")]
pub fn session_start(session_id: String, id: String) -> String {
    let Some(session_id) = parse_session(&session_id) else {
        return "invalid session id".to_owned();
    };
    librustdesk::flutter_ffi::session_start_ohos(session_id, id)
}

/// Close a session and forget it, so the same id can be used again.
#[napi(js_name = "sessionClose")]
pub fn session_close(session_id: String) {
    if let Some(session_id) = parse_session(&session_id) {
        librustdesk::flutter_ffi::session_close(session_id);
        librustdesk::flutter_ffi::session_forget_ohos(session_id);
    }
}

/// A decoded frame, ready to become an image.
#[napi(object)]
pub struct RgbaFrame {
    pub width: u32,
    pub height: u32,
    /// RGBA, four bytes per pixel, `width * height * 4` long.
    pub data: Buffer,
}

/// Copy the frame waiting for `display`, or null when none has arrived.
///
/// Copied rather than lent: the buffer belongs to the video handler and is reused as soon as it
/// is released, so anything else would be a use-after-free across the N-API boundary. Release it
/// with [`session_release_rgba`] once consumed, or no further frames are decoded.
#[napi(js_name = "sessionTakeRgba")]
pub fn session_take_rgba(session_id: String, display: u32) -> Option<RgbaFrame> {
    let session_id = parse_session(&session_id)?;
    let frame = librustdesk::flutter::ohos_get_rgba(&session_id, display as usize)?;
    Some(RgbaFrame {
        width: frame.width as u32,
        height: frame.height as u32,
        data: Buffer::from(frame.data),
    })
}

/// Release the frame for `display`, letting the video handler decode the next one.
#[napi(js_name = "sessionReleaseRgba")]
pub fn session_release_rgba(session_id: String, display: u32) {
    if let Some(session_id) = parse_session(&session_id) {
        librustdesk::flutter_ffi::session_release_rgba(session_id, display as usize);
    }
}

/// Drain the core's UI events, as a JSON array of short strings.
///
/// HarmonyOS has no Dart stream to receive these, so the front end polls for them. They carry
/// status only -- the picture comes from [`session_take_rgba`] -- so a missed poll costs a
/// notification and nothing more.
#[napi(js_name = "pollUiEvents")]
pub fn poll_ui_events() -> String {
    librustdesk::flutter_ffi::ohos_poll_ui_events()
}

// --- video surface ------------------------------------------------------------
//
// ArkUI's XComponent hands out a surface, and the frames go straight into it from Rust. Nothing
// crosses this boundary per frame -- see src/surface.rs for why.

/// Bind the surface an XComponent created. Empty string on success, or the failure message.
///
/// `surfaceId` is the decimal string from `XComponentController.getXComponentSurfaceId()`.
#[napi(js_name = "videoSurfaceAttach")]
pub fn video_surface_attach(surface_id: String) -> String {
    surface::attach(&surface_id)
}

/// Render the session's display into the attached surface until stopped.
///
/// Empty string on success. Frames are not returned to ArkTS: the render loop lives in Rust so
/// that a frame is written straight into the surface buffer rather than copied out and back.
#[napi(js_name = "videoStart")]
pub fn video_start(session_id: String, display: u32) -> String {
    surface::start(session_id, display as usize)
}

/// Stop rendering. The render thread exits on its next poll.
#[napi(js_name = "videoStop")]
pub fn video_stop() {
    surface::stop()
}

/// Release the surface and stop rendering. Call when the XComponent goes away.
#[napi(js_name = "videoSurfaceDetach")]
pub fn video_surface_detach() {
    surface::detach()
}

/// Whether a surface is currently bound.
#[napi(js_name = "videoIsAttached")]
pub fn video_is_attached() -> bool {
    surface::is_attached()
}
