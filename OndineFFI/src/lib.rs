use std::ffi::{CStr, CString, c_char};

/// Renders Mermaid `source` to SVG. On success, `*svg` receives a string and the return value is true.
/// On failure, `*error` receives Ondine's message and the return value is false. Free either with `ondine_free`.
///
/// # Safety
/// `source` must be a valid NUL-terminated UTF-8 string; `svg` and `error` must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ondine_render(
    source: *const c_char,
    now: f64,
    svg: *mut *mut c_char,
    error: *mut *mut c_char,
) -> bool {
    let source = unsafe { CStr::from_ptr(source) }.to_string_lossy();
    match compiler::render(&source, "", now) {
        Ok(rendered) => {
            unsafe { *svg = into_c_string(rendered.svg) };
            true
        }
        Err(failure) => {
            unsafe { *error = into_c_string(failure.message) };
            false
        }
    }
}

/// Frees a string returned by `ondine_render`.
///
/// # Safety
/// `string` must come from `ondine_render` and not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ondine_free(string: *mut c_char) {
    if !string.is_null() {
        drop(unsafe { CString::from_raw(string) });
    }
}

fn into_c_string(text: String) -> *mut c_char {
    // Diagram text never contains NUL bytes; a stray one would only truncate the message.
    CString::new(text.replace('\0', "")).unwrap_or_default().into_raw()
}
