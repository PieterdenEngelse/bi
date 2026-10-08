use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    state::{AppState, Item, NewItem},
};

pub async fn list(State(state): State<AppState>) -> Json<Vec<Item>> {
    Json(state.list())
}

pub async fn get_one(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Item>> {
    state
        .get(id)
        .map(Json)
        .ok_or_else(|| AppError::NotFound(format!("no item {id}")))
}

pub async fn create(
    State(state): State<AppState>,
    Json(body): Json<NewItem>,
) -> AppResult<(StatusCode, Json<Item>)> {
    let name = body.name.trim().to_string();
    if name.is_empty() {
        return Err(AppError::BadRequest("name must not be empty".into()));
    }
    Ok((StatusCode::CREATED, Json(state.create(name))))
}

#[derive(Debug, Deserialize)]
pub struct UpdateItem {
    pub done: bool,
}

pub async fn update(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateItem>,
) -> AppResult<Json<Item>> {
    state
        .set_done(id, body.done)
        .map(Json)
        .ok_or_else(|| AppError::NotFound(format!("no item {id}")))
}

pub async fn delete(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    if state.delete(id) {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotFound(format!("no item {id}")))
    }
}
