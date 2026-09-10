mod keyboard;
/// cbindgen:ignore
pub mod platform;
#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
pub use platform::{
    clip_cursor, get_cursor, get_cursor_data, get_cursor_pos, get_focused_display,
    set_cursor_pos, start_os_service,
};
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
/// cbindgen:ignore
mod server;
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
pub use self::server::*;
mod client;
mod lan;
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
mod rendezvous_mediator;
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
pub use self::rendezvous_mediator::*;
/// cbindgen:ignore
pub mod common;
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
pub mod ipc;
#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    target_env = "ohos",
    feature = "flutter"
)))]
pub mod ui;
mod version;
pub use version::*;
// The mobile session layer (flutter::get_cur_session and the FlutterSession it hands
// back) is what the client uses on every mobile target, so HarmonyOS takes the same path
// as android/ios.
#[cfg(any(target_os = "android", target_os = "ios", target_env = "ohos", feature = "flutter"))]
pub mod flutter;
#[cfg(any(target_os = "android", target_os = "ios", target_env = "ohos", feature = "flutter"))]
pub mod flutter_ffi;
// bridge_generated is flutter_rust_bridge codegen output and is checked in only for the
// builds that regenerate it. HarmonyOS exposes its FFI through flutter_ffi and ohos-rs
// instead, so it is excluded there.
#[cfg(all(
    any(target_os = "android", target_os = "ios", feature = "flutter"),
    not(target_env = "ohos")
))]
mod bridge_generated;
use common::*;
mod auth_2fa;
#[cfg(not(any(target_os = "ios", target_env = "ohos")))]
mod clipboard;
#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
pub mod core_main;
mod custom_server;
mod lang;
#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
mod port_forward;
mod port_forward_mux;

#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
mod tray;

#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
mod whiteboard;

#[cfg(not(any(target_os = "android", target_os = "ios", target_env = "ohos")))]
mod updater;

mod ui_cm_interface;
mod ui_interface;
mod ui_session_interface;

mod hbbs_http;

#[cfg(all(
    any(target_os = "windows", target_os = "linux", target_os = "macos"),
    not(target_env = "ohos")
))]
pub mod clipboard_file;

pub mod privacy_mode;

#[cfg(windows)]
pub mod virtual_display_manager;

mod kcp_stream;
