use std::env;

fn main() {
    napi_build_ohos::setup();

    // The surface renderer in src/surface.rs calls into the graphics stack directly (see that
    // file for why ArkUI's own image path cannot be used for video). Those symbols live in the
    // platform's native window library, which is a system library on device and is provided as a
    // stub by the OHOS NDK's sysroot at link time.
    //
    // This must be decided from CARGO_CFG_TARGET_ENV rather than `#[cfg(target_env = "ohos")]`: a
    // build script is compiled for the HOST, so a cfg test here answers a question about the
    // machine doing the build, not the device being built for. On a Windows host the cfg is false
    // even when the target is ohos, the link library is never named, and the module links with
    // those symbols undefined -- which does not fail the build, because a cdylib is allowed to
    // have undefined symbols, but does fail to load on device with the ArkTS import coming back
    // undefined. That is the same shape as the earlier libsodium and libssl failures.
    if env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("ohos") {
        println!("cargo:rustc-link-lib=dylib=native_window");
    }
}
