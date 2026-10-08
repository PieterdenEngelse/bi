pub mod health;
pub mod items;

use axum::{routing::get, Router};
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::state::AppState;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health::health))
        .route("/api/items", get(items::list).post(items::create))
        .route(
            // axum 0.8 uses {id}, not the :id of 0.7 and earlier.
            "/api/items/{id}",
            get(items::get_one).patch(items::update).delete(items::delete),
        )
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state)
}
