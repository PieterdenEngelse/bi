/// The Rust side of the UI.
///
/// Deliberately thin: the engine is authoritative and the QML talks to it over
/// HTTP, so this exists to supply what QML cannot work out for itself - where
/// the engine is listening. Keeping data access in QML is what lets the same
/// QML build unchanged for WebAssembly in phase 3.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        /// An alias to the QString type
        type QString = cxx_qt_lib::QString;
    }

    // cxx-qt >=0.7 does NOT case-convert automatically: a Rust `api_base`
    // stays `api_base` in QML unless told otherwise, and `dash.apiBase` then
    // silently reads as undefined. #[auto_cxx_name] applies camelCase to the
    // whole block, so Rust stays snake_case and QML gets what it expects
    // without per-item annotations as this grows.
    #[auto_cxx_name]
    extern "RustQt" {
        /// Application-level state exposed to QML.
        #[qobject]
        #[qml_element]
        #[qproperty(QString, api_base)]
        #[qproperty(QString, version)]
        #[qproperty(QString, built)]
        type Dash = super::DashRust;
    }
}

use cxx_qt_lib::QString;

pub struct DashRust {
    api_base: QString,
    version: QString,
    built: QString,
}

impl Default for DashRust {
    /// NIXDASH_PORT is read here rather than hardcoded in QML so the desktop
    /// UI follows the engine when it is moved off the default port. Loopback
    /// is not configurable - the engine only ever binds 127.0.0.1.
    ///
    /// The version and build date join it for the same reason: QML cannot
    /// work either out for itself.
    fn default() -> Self {
        let port = std::env::var("NIXDASH_PORT")
            .ok()
            .and_then(|p| p.parse::<u16>().ok())
            .unwrap_or(3100);
        Self {
            api_base: QString::from(&format!("http://127.0.0.1:{port}")),
            // Both are compile-time constants, which is the point: they
            // describe the binary you are looking at, so neither can be
            // fetched from the engine - that is a different build with its
            // own version, and asking it would answer the wrong question.
            version: QString::from(env!("CARGO_PKG_VERSION")),
            built: QString::from(env!("NIXDASH_BUILT")),
        }
    }
}
