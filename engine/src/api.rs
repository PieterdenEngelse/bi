use axum::{
    extract::{Path, Query, State},
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::json;
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
}

pub fn router(registry: Registry) -> Router {
    router_with(AppState { registry, actions: Actions::with_defaults() })
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
    let Ok(origin) = origin.to_str() else { return false };
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
