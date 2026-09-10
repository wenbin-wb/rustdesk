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
//! ```
//!
//! Only exports whose signatures are plain N-API compatible types are wrapped for now.
//! The bulk of `flutter_ffi` returns flutter_rust_bridge's `SyncReturn` and takes
//! `StreamSink` parameters; those need a deliberate shape decision per family of
//! functions (values unwrapped, streams replaced by the ohos event channel) rather than
//! a mechanical translation, so they are added in batches rather than all at once.
//!
//! See flutter/ohos/PLAN.md for the P2 breakdown.

#[macro_use]
extern crate napi_derive_ohos;

/// Identity of the bridge itself, for smoke-testing that the module loaded and that
/// ArkTS can call across the boundary.
#[napi]
pub fn bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// The core's version, read through the bridge. Confirms the core is linked in and
/// callable, not merely present in the dependency graph.
#[napi(js_name = "mainGetVersion")]
pub fn main_get_version() -> String {
    librustdesk::flutter_ffi::main_get_version()
}

/// Build date of the linked core, useful for confirming which artifact a device runs.
#[napi(js_name = "mainGetBuildDate")]
pub fn main_get_build_date() -> String {
    librustdesk::flutter_ffi::main_get_build_date()
}

/// The local device's RustDesk ID. This is one of the first calls ArkTS needs, and it
/// goes through the real core path rather than a stub.
#[napi(js_name = "mainGetUuid")]
pub fn main_get_uuid() -> String {
    librustdesk::flutter_ffi::main_get_uuid()
}
