use axum::{
    extract::{Path, Query, State},
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use tower_http::{
    cors::{AllowOrigin, CorsLayer},
    trace::TraceLayer,
};

use crate::{actions::Actions, registry::Registry};

/// Router state: panels to read, actions to suggest and run.
#[derive(Clone)]
pub struct AppState {
    pub registry: Registry,
    pub actions: Actions,
    /// The port actually bound, so the settings endpoint can report what is
    /// live alongside what is declared.
    pub port: u16,
}

pub fn router(registry: Registry) -> Router {
    router_with(AppState {
        registry,
        actions: Actions::with_defaults(),
        port: std::env::var("NIXDASH_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(3100),
    })
}

/// Is this origin one of our own loopback UIs?
///
/// This used to be `CorsLayer::permissive()`, which was harmless while every
/// route was a GET of read-only data. It is not harmless now: with a POST that
/// can start a privileged action, permissive CORS means any page in the
/// browser - any site, not just ours - can ask the engine to begin a rebuild
/// and raise a polkit prompt the user did not go looking for. A prompt you did
/// not expect is a prompt you might click through.
///
/// Binding to loopback does not help here: the request comes *from* the
/// browser, which is on loopback. So the origin has to be checked. Our wasm UI
/// is served from a static server on another port, so an exact origin will not
/// do - any loopback port, but only loopback.
fn is_loopback_origin(origin: &HeaderValue) -> bool {
    let Ok(origin) = origin.to_str() else {
        return false;
    };
    let Some(rest) = origin
        .strip_prefix("http://")
        .or_else(|| origin.strip_prefix("https://"))
    else {
        return false;
    };
    // Split the port off, taking care with the bracketed IPv6 form.
    let host = match rest.strip_prefix('[') {
        Some(after) => match after.split_once(']') {
            Some((h, _port)) => h,
            None => return false,
        },
        None => rest.split(':').next().unwrap_or(""),
    };
    matches!(host, "localhost" | "127.0.0.1" | "::1")
}

pub fn router_with(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin, _req| {
            is_loopback_origin(origin)
        }))
        .allow_methods([Method::GET, Method::POST])
        .allow_headers([axum::http::header::CONTENT_TYPE]);

    Router::new()
        .route("/health", get(health))
        .route("/api/panels", get(list_panels))
        .route("/api/actions", get(list_actions))
        // axum 0.8 path params are {id}, not :id
        .route("/api/panels/{id}", get(panel_history))
        .route("/api/actions/{id}/run", post(run_action))
        .route("/api/settings", get(list_settings).post(write_setting))
        .route("/api/settings/preview", post(preview_setting))
        .route("/api/devshell", get(list_devshell).post(toggle_devshell))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state)
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok", "version": env!("CARGO_PKG_VERSION") }))
}

async fn list_panels(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(json!({ "panels": state.registry.summaries() }))
}

async fn list_actions(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::to_value(state.actions.report()).unwrap_or_else(|_| json!({})))
}

/// Execute one suggested action.
///
/// The action is looked up by id and its *own* `RunCommand` is executed. The
/// request body is ignored entirely - the caller names which action to run and
/// nothing else. It cannot supply a program, an argument, or a flag. That is
/// the one property worth protecting here: the set of things this endpoint can
/// ever execute is the set of actions the providers decided to offer, and it is
/// fixed at compile time.
///
/// Root, where needed, comes from pkexec: polkit prompts, and the prompt is
/// the authorisation. The engine has no privilege to lend.
async fn run_action(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let report = state.actions.report();
    let action = report
        .actions
        .into_iter()
        .find(|a| a.id == id)
        // Actions are derived from live state, so an id can legitimately
        // disappear between listing and running - the unit recovered, the
        // rebuild already happened. That is a 404, not an error.
        .ok_or_else(|| ApiError::NotFound(format!("no action {id}")))?;

    let Some(command) = action.run.clone() else {
        return Err(ApiError::NotRunnable(format!(
            "{id} is not something that can be run: it is configuration to \
             apply, not a command to execute"
        )));
    };

    // spawn_blocking, because `run` blocks the thread for as long as the
    // command takes - and `nixos-rebuild switch` takes minutes. On a tokio
    // worker that would stall every other request, including the polling the
    // UI does to stay current.
    let outcome = tokio::task::spawn_blocking(move || crate::actions::runner::run(&command))
        .await
        .map_err(|e| ApiError::Internal(format!("run task failed: {e}")))?;

    Ok(Json(json!({
        "action": action.id,
        "title": action.title,
        "outcome": outcome,
        "ok": outcome.succeeded(),
    })))
}

/// A request to change one setting.
///
/// Note the contrast with the run endpoint, which deliberately takes **no**
/// body at all. The difference is what the body can express: there, a body
/// would widen the set of executable things beyond what the providers offer;
/// here it names one key from a fixed list and a value that is range- or
/// enum-checked before anything is written. The surface stays closed either
/// way - this one just needs two words instead of one.
#[derive(Debug, Deserialize)]
pub struct SettingChange {
    key: String,
    value: crate::settings::SettingValue,
}

fn settings_file() -> Result<(std::path::PathBuf, String), ApiError> {
    let path = crate::settings::settings_path()
        .ok_or_else(|| ApiError::Internal("no HOME, cannot locate settings".into()))?;
    // Absent is normal - nothing has been changed from the app yet - and must
    // read as an empty declaration rather than an error.
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    Ok((path, text))
}

/// Every setting the app may change, with what is declared and what is live.
///
/// Both are reported because on a declarative system they are genuinely two
/// different facts, and the gap between them is the thing worth seeing: a
/// value written here does nothing until the next `home-manager switch`.
async fn list_settings(State(state): State<AppState>) -> Result<Json<serde_json::Value>, ApiError> {
    let (path, text) = settings_file()?;
    let declared = crate::settings::read_declared(&text);

    let effective = json!({
        "port": state.port,
        "logLevel": std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
    });

    let settings: Vec<serde_json::Value> = crate::settings::known()
        .into_iter()
        .map(|s| {
            let value = declared
                .iter()
                .find(|(k, _)| *k == s.key)
                .map(|(_, v)| serde_json::to_value(v).unwrap_or(Value::Null))
                .unwrap_or(Value::Null);
            let mut obj = serde_json::to_value(&s).unwrap_or_else(|_| json!({}));
            if let Some(map) = obj.as_object_mut() {
                map.insert("declared".into(), value);
            }
            obj
        })
        .collect();

    Ok(Json(json!({
        "path": path.display().to_string(),
        "exists": path.exists(),
        "settings": settings,
        "effective": effective,
    })))
}

/// What a change would do, without doing it.
async fn preview_setting(
    Json(change): Json<SettingChange>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let (path, text) = settings_file()?;
    let plan = crate::settings::plan(
        &text,
        &path.display().to_string(),
        &change.key,
        &change.value,
    )
    .map_err(|e| ApiError::NotRunnable(e.to_string()))?;
    Ok(Json(
        serde_json::to_value(plan).unwrap_or_else(|_| json!({})),
    ))
}

/// Write one setting.
///
/// Writes the single file the engine owns, regenerated whole. It does not
/// rebuild: the response says what still has to happen, because on this
/// system writing Nix source and applying it are separate acts and conflating
/// them would be the lie this page exists to avoid.
async fn write_setting(
    Json(change): Json<SettingChange>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let (path, text) = settings_file()?;
    let plan = crate::settings::plan(
        &text,
        &path.display().to_string(),
        &change.key,
        &change.value,
    )
    .map_err(|e| ApiError::NotRunnable(e.to_string()))?;

    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)
            .map_err(|e| ApiError::Internal(format!("creating {}: {e}", dir.display())))?;
    }
    std::fs::write(&path, &plan.rendered)
        .map_err(|e| ApiError::Internal(format!("writing {}: {e}", path.display())))?;

    tracing::info!(key = %plan.key, path = %path.display(), "wrote setting");

    Ok(Json(json!({
        "written": true,
        "path": path.display().to_string(),
        "key": plan.key,
        "from": plan.from,
        "to": plan.to,
        "diff": plan.diff,
        "applied": false,
        "next_step": "Run `home-manager switch`, then restart the engine. \
                      Nothing has changed yet - this only edited Nix source.",
    })))
}

#[derive(Debug, Deserialize)]
pub struct DevshellToggle {
    key: String,
    enabled: bool,
}

fn devshell_file() -> Result<(std::path::PathBuf, String), ApiError> {
    let path = crate::devshell::extras_path()
        .ok_or_else(|| ApiError::NotFound("no project directory - nothing to configure".into()))?;
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    Ok((path, text))
}

/// Dev shell additions the app can toggle, and whether each is live yet.
///
/// `verified_by` names the panel stat that confirms it, so "enabled" and
/// "actually there" stay separate facts - the same distinction the settings
/// page makes between declared and in effect.
async fn list_devshell(State(state): State<AppState>) -> Result<Json<serde_json::Value>, ApiError> {
    let (path, text) = devshell_file()?;
    let enabled = crate::devshell::read_enabled(&text);

    // Look the confirming stat up in the panel that owns it, rather than
    // re-measuring here - one source for the fact.
    let panels = state.registry.summaries();
    let live = |reference: &str| -> Value {
        let Some((panel_id, stat)) = reference.split_once('.') else {
            return Value::Null;
        };
        panels
            .iter()
            .find(|p| p.meta.id == panel_id)
            .and_then(|p| p.latest.as_ref())
            .map(|s| s.value[stat].clone())
            .unwrap_or(Value::Null)
    };

    let extras: Vec<Value> = crate::devshell::known()
        .into_iter()
        .map(|e| {
            let mut obj = serde_json::to_value(&e).unwrap_or_else(|_| json!({}));
            if let Some(map) = obj.as_object_mut() {
                map.insert(
                    "enabled".into(),
                    Value::Bool(enabled.iter().any(|k| k == e.key)),
                );
                map.insert("live".into(), live(e.verified_by));
            }
            obj
        })
        .collect();

    Ok(Json(json!({
        "path": path.display().to_string(),
        "exists": path.exists(),
        "extras": extras,
    })))
}

/// Turn one addition on or off.
///
/// Writes the generated file and nothing else. Taking effect needs a new
/// shell - `nix develop` - which the response says rather than leaving you to
/// wonder why the panel has not moved.
async fn toggle_devshell(
    Json(toggle): Json<DevshellToggle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let (path, text) = devshell_file()?;
    let plan = crate::devshell::plan(
        &text,
        &path.display().to_string(),
        &toggle.key,
        toggle.enabled,
    )
    .map_err(|e| ApiError::NotRunnable(e.to_string()))?;

    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)
            .map_err(|e| ApiError::Internal(format!("creating {}: {e}", dir.display())))?;
    }
    std::fs::write(&path, &plan.rendered)
        .map_err(|e| ApiError::Internal(format!("writing {}: {e}", path.display())))?;

    tracing::info!(key = %plan.key, enabled = plan.enabled, "toggled dev shell extra");

    Ok(Json(json!({
        "written": true,
        "path": plan.path,
        "key": plan.key,
        "enabled": plan.enabled,
        "diff": plan.diff,
        "live": false,
        "next_step": "Re-enter the development shell with `nix develop` for \
                      this to take effect. Nothing has changed in the shell \
                      you already have open.",
    })))
}

#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    /// Number of samples to return, newest last.
    limit: Option<usize>,
}

async fn panel_history(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(q): Query<HistoryQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let panel = state
        .registry
        .get(&id)
        .ok_or_else(|| ApiError::NotFound(format!("no panel {id}")))?;

    let limit = q.limit.unwrap_or(120).min(1000);
    Ok(Json(json!({
        "meta": panel.meta,
        "error": panel.error(),
        "samples": panel.history(limit),
    })))
}

pub enum ApiError {
    NotFound(String),
    /// The action exists but has nothing executable - a Nix snippet.
    NotRunnable(String),
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            ApiError::NotFound(m) => (StatusCode::NOT_FOUND, m),
            // 422, not 404: the action is real and was found, it just is not
            // the kind of thing that runs.
            ApiError::NotRunnable(m) => (StatusCode::UNPROCESSABLE_ENTITY, m),
            ApiError::Internal(m) => (StatusCode::INTERNAL_SERVER_ERROR, m),
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}
