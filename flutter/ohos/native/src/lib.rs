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
