//! Node-API bridge between the RustDesk core and ArkTS on HarmonyOS.
//!
//! HarmonyOS has no Dart isolate, so the Flutter-facing bridge in the core crate
//! (`src/flutter_ffi.rs`, generated against flutter_rust_bridge) is not usable from
//! ArkTS. Instead the core is compiled into `librustdesk.so` and reached through these
//! N-API exports, which ArkTS imports as:
//!
//! ```ts
//! import bridge from 'librustdesk_ohos.so';
//! bridge.bridgeVersion();
//! ```
//!
//! See flutter/ohos/PLAN.md for why ohos-rs was chosen over a hand-written C++ N-API
//! layer, and for the P2 work breakdown.

#[macro_use]
extern crate napi_derive_ohos;

/// Identity of the bridge itself, for smoke-testing that the module loaded and that
/// ArkTS can call across the boundary.
#[napi]
pub fn bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}
