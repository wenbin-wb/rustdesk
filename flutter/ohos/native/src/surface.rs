//! Renders the core's decoded frames into the HarmonyOS surface an XComponent provides.
//!
//! Why this exists rather than an ArkTS-side image: ArkUI's `PixelMap` has no way to signal that
//! its contents were changed, so mutating one in place does not redraw, and building a new one
//! per frame costs a full `width * height * 4` allocation -- about 8 MB per frame at 1080p. An
//! XComponent hands out a surface instead, and the frame is written straight into the buffer
//! behind it. That is also the route the reference HarmonyOS client takes.
//!
//! The whole loop lives here rather than in ArkTS: ArkTS attaches the surface and asks for the
//! stream to start, and from then on frames go from the core to the screen without crossing the
//! N-API boundary at all.
//!
//! ### Buffer contract
//!
//! A surface buffer's `stride` is a multiple the graphics stack chooses and is not necessarily
//! `width * 4`, so rows are copied one at a time into the buffer rather than as a single block.
//! Assuming otherwise shears the image.
//!
//! Every requested buffer must be flushed or the surface stalls, and the fence returned by the
//! request has to be handed back on flush. A failure between the two would leave the buffer
//! outstanding forever, so the copy and the flush are kept adjacent with no early return between
//! them.

use std::os::raw::{c_int, c_void};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// `NativeWindowOperation::SET_BUFFER_GEOMETRY`, the first variant of the enum.
const SET_BUFFER_GEOMETRY: c_int = 0;
/// `NativeWindowOperation::SET_FORMAT`: SET_BUFFER_GEOMETRY, GET_BUFFER_GEOMETRY, GET_FORMAT, then
/// this.
const SET_FORMAT: c_int = 3;
/// `NATIVEBUFFER_PIXEL_FMT_RGBA_8888`, counted from `CLUT8 = 0` in buffer_common.h.
const PIXEL_FMT_RGBA_8888: c_int = 12;

/// How long to wait between polls when the core has no new frame. Frames arrive at the video
/// stream's rate, so this only bounds the latency of noticing one.
const POLL_INTERVAL: Duration = Duration::from_millis(4);

#[repr(C)]
struct Rect {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
}

/// Dirty region handed to flush. A null `rects` means "the whole buffer changed", which is what
/// a video frame always is.
#[repr(C)]
struct Region {
    rects: *mut Rect,
    rect_number: u32,
}

/// Mirrors `BufferHandle` from native_window/buffer_handle.h. Only the leading fields are read;
/// the trailing flexible array is deliberately omitted, and the struct is only ever used through
/// a pointer the graphics stack owns.
#[repr(C)]
struct BufferHandle {
    fd: c_int,
    width: c_int,
    stride: c_int,
    height: c_int,
    size: c_int,
    format: c_int,
    usage: u64,
    vir_addr: *mut c_void,
    key: c_int,
    phy_addr: u64,
    reserve_fds: u32,
    reserve_ints: u32,
}

extern "C" {
    fn OH_NativeWindow_CreateNativeWindowFromSurfaceId(
        surface_id: u64,
        window: *mut *mut c_void,
    ) -> c_int;
    fn OH_NativeWindow_NativeWindowHandleOpt(window: *mut c_void, code: c_int, ...) -> c_int;
    fn OH_NativeWindow_NativeWindowRequestBuffer(
        window: *mut c_void,
        buffer: *mut *mut c_void,
        fence_fd: *mut c_int,
    ) -> c_int;
    fn OH_NativeWindow_NativeWindowFlushBuffer(
        window: *mut c_void,
        buffer: *mut c_void,
        fence_fd: c_int,
        region: Region,
    ) -> c_int;
    fn OH_NativeWindow_GetBufferHandleFromNative(buffer: *mut c_void) -> *mut BufferHandle;
    fn OH_NativeWindow_NativeObjectUnreference(obj: *mut c_void) -> c_int;
    fn OH_NativeWindow_DestroyNativeWindow(window: *mut c_void) -> c_int;
}

/// What the render thread is drawing and where.
struct RenderTarget {
    /// `OHNativeWindow *`, owned by this struct until `detach`.
    window: *mut c_void,
    /// Geometry already applied, so it is only set again when the frame size changes.
    geometry: Option<(usize, usize)>,
    session_id: String,
    display: usize,
}

// The raw window pointer is only ever used from the render thread, and the Mutex below is what
// enforces that. Nothing else may touch it.
unsafe impl Send for RenderTarget {}

lazy_static::lazy_static! {
    static ref TARGET: Mutex<Option<RenderTarget>> = Mutex::new(None);
}

static RENDERING: AtomicBool = AtomicBool::new(false);

/// Whether a surface has been attached and not yet detached.
pub fn is_attached() -> bool {
    TARGET.lock().map(|t| t.is_some()).unwrap_or(false)
}

/// Attach the surface an XComponent handed out.
///
/// `surface_id` is the decimal string ArkTS gets from `XComponentController.getXComponentSurfaceId()`,
/// not a raw number, because that is the only form ArkUI exposes. Returns an empty string on
/// success or a message describing the failure.
pub fn attach(surface_id: &str) -> String {
    let id: u64 = match surface_id.trim().parse() {
        Ok(v) => v,
        Err(_) => return format!("surfaceId is not a number: {:?}", surface_id),
    };
    if id == 0 {
        return "surfaceId is zero".to_owned();
    }
    let mut guard = match TARGET.lock() {
        Ok(g) => g,
        Err(_) => return "render target lock poisoned".to_owned(),
    };
    // A second attach without a detach would leak the first window.
    if let Some(old) = guard.take() {
        unsafe { OH_NativeWindow_DestroyNativeWindow(old.window) };
    }
    let mut window: *mut c_void = std::ptr::null_mut();
    let rc = unsafe { OH_NativeWindow_CreateNativeWindowFromSurfaceId(id, &mut window) };
    if rc != 0 || window.is_null() {
        return format!("CreateNativeWindowFromSurfaceId failed: rc={}", rc);
    }
    *guard = Some(RenderTarget {
        window,
        geometry: None,
        session_id: String::new(),
        display: 0,
    });
    String::new()
}

/// Release the surface. Safe to call when nothing is attached.
pub fn detach() {
    stop();
    let taken = TARGET.lock().ok().and_then(|mut g| g.take());
    if let Some(t) = taken {
        unsafe { OH_NativeWindow_DestroyNativeWindow(t.window) };
    }
}

/// Render `session_id`'s display into the attached surface until [`stop`] is called.
///
/// Returns an empty string on success. The thread polls the core rather than being pushed to:
/// the core has no hook to call into ArkTS, and a frame is a large buffer that should not be
/// copied through the N-API boundary per frame.
pub fn start(session_id: String, display: usize) -> String {
    if !is_attached() {
        return "no surface attached".to_owned();
    }
    if RENDERING.swap(true, Ordering::SeqCst) {
        return "already rendering".to_owned();
    }
    {
        let mut guard = match TARGET.lock() {
            Ok(g) => g,
            Err(_) => {
                RENDERING.store(false, Ordering::SeqCst);
                return "render target lock poisoned".to_owned();
            }
        };
        if let Some(t) = guard.as_mut() {
            t.session_id = session_id.clone();
            t.display = display;
            // Force geometry to be applied for the new stream.
            t.geometry = None;
        }
    }

    let session = match uuid::Uuid::parse_str(&session_id) {
        Ok(u) => u,
        Err(_) => {
            RENDERING.store(false, Ordering::SeqCst);
            return "invalid session id".to_owned();
        }
    };

    std::thread::Builder::new()
        .name("ohos-video".to_owned())
        .spawn(move || render_loop(session, display))
        .map(|_| String::new())
        .unwrap_or_else(|e| {
            RENDERING.store(false, Ordering::SeqCst);
            format!("could not start the render thread: {}", e)
        })
}

/// Stop rendering. The thread notices on its next poll and exits.
pub fn stop() {
    RENDERING.store(false, Ordering::SeqCst);
}

fn render_loop(session_id: uuid::Uuid, display: usize) {
    log::info!(
        "video render loop started for session {}, display {}",
        session_id,
        display
    );
    while RENDERING.load(Ordering::SeqCst) {
        let frame = librustdesk::flutter::ohos_get_rgba(&session_id, display);
        match frame {
            Some(frame) if !frame.data.is_empty() && frame.width > 0 && frame.height > 0 => {
                if let Err(e) = draw(&frame) {
                    // A draw failure is usually a transient surface problem (a resize, or the
                    // window going away). Drop the frame and keep going rather than tearing the
                    // loop down; the next frame will tell us if the surface is really gone.
                    log::warn!("video draw failed: {}", e);
                }
                // Release regardless of whether the draw succeeded: holding the frame back
                // would stall the core's decoder, so a failed draw would also stop the stream.
                librustdesk::flutter::ohos_next_rgba(&session_id, display);
            }
            _ => std::thread::sleep(POLL_INTERVAL),
        }
    }
    log::info!("video render loop stopped for session {}", session_id);
}

/// Write one frame into the surface.
fn draw(frame: &librustdesk::flutter::OhosFrame) -> Result<(), String> {
    let mut guard = TARGET.lock().map_err(|_| "lock poisoned".to_owned())?;
    let target = guard.as_mut().ok_or_else(|| "no surface".to_owned())?;
    if target.window.is_null() {
        return Err("surface window is null".to_owned());
    }

    if target.geometry != Some((frame.width, frame.height)) {
        let rc = unsafe {
            OH_NativeWindow_NativeWindowHandleOpt(
                target.window,
                SET_BUFFER_GEOMETRY,
                frame.width as c_int,
                frame.height as c_int,
            )
        };
        if rc != 0 {
            return Err(format!("set geometry failed: rc={}", rc));
        }
        // Set once alongside geometry; the surface keeps it for later buffers.
        let rc = unsafe {
            OH_NativeWindow_NativeWindowHandleOpt(target.window, SET_FORMAT, PIXEL_FMT_RGBA_8888)
        };
        if rc != 0 {
            return Err(format!("set format failed: rc={}", rc));
        }
        target.geometry = Some((frame.width, frame.height));
    }

    let mut buffer: *mut c_void = std::ptr::null_mut();
    let mut fence_fd: c_int = -1;
    let rc = unsafe {
        OH_NativeWindow_NativeWindowRequestBuffer(target.window, &mut buffer, &mut fence_fd)
    };
    if rc != 0 || buffer.is_null() {
        return Err(format!("request buffer failed: rc={}", rc));
    }

    // From here the buffer is outstanding and MUST be flushed. Everything that can fail is
    // folded into `copied` so there is a single path to the flush below.
    let copied = unsafe {
        let handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
        if handle.is_null() || (*handle).vir_addr.is_null() {
            Err("buffer has no mapped address".to_owned())
        } else {
            let handle = &*handle;
            let stride = handle.stride as usize;
            let src_row = frame.width * 4;
            let dst_height = handle.height as usize;
            // The surface may be a different size than the frame while a resize settles; copy
            // only the rows both have, so this can never write past the buffer.
            let rows = frame.height.min(dst_height);
            if stride < src_row {
                Err(format!(
                    "stride {} is smaller than a row ({})",
                    stride, src_row
                ))
            } else {
                let dst = handle.vir_addr as *mut u8;
                for y in 0..rows {
                    let src = frame.data.as_ptr().add(y * src_row);
                    // Row by row: the buffer's stride is the graphics stack's choice and is not
                    // necessarily width * 4, so a single block copy would shear the image.
                    std::ptr::copy_nonoverlapping(src, dst.add(y * stride), src_row);
                }
                Ok(())
            }
        }
    };

    let flush_rc = unsafe {
        OH_NativeWindow_NativeWindowFlushBuffer(
            target.window,
            buffer,
            fence_fd,
            Region {
                rects: std::ptr::null_mut(),
                rect_number: 0,
            },
        )
    };
    if flush_rc != 0 {
        // Unreference so the buffer is not leaked; the surface will hand out a fresh one.
        unsafe { OH_NativeWindow_NativeObjectUnreference(buffer) };
        return Err(format!("flush failed: rc={}", flush_rc));
    }

    copied
}
