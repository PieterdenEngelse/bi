use axum::{
    body::Body,
    http::{header, Request, StatusCode},
};
use b1::{router, AppState};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt; // oneshot

async fn send(app: axum::Router, req: Request<Body>) -> (StatusCode, Value) {
    let res = app.oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let body = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap()
    };
    (status, body)
}

fn post(path: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(path)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn get(path: &str) -> Request<Body> {
    Request::builder().uri(path).body(Body::empty()).unwrap()
}

#[tokio::test]
async fn health_reports_ok() {
    let (status, body) = send(router(AppState::new()), get("/health")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");
}

#[tokio::test]
async fn create_then_fetch_roundtrips() {
    let state = AppState::new();

    let (status, created) =
        send(router(state.clone()), post("/api/items", json!({"name": "write tests"}))).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(created["name"], "write tests");
    assert_eq!(created["done"], false);

    let id = created["id"].as_str().unwrap();
    let (status, fetched) = send(router(state), get(&format!("/api/items/{id}"))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(fetched["id"], id);
}

#[tokio::test]
async fn rejects_empty_name() {
    let (status, body) =
        send(router(AppState::new()), post("/api/items", json!({"name": "   "}))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("empty"));
}

#[tokio::test]
async fn unknown_id_is_404() {
    let id = uuid::Uuid::new_v4();
    let (status, _) = send(router(AppState::new()), get(&format!("/api/items/{id}"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn patch_marks_done_and_delete_removes() {
    let state = AppState::new();
    let (_, created) =
        send(router(state.clone()), post("/api/items", json!({"name": "ship it"}))).await;
    let id = created["id"].as_str().unwrap().to_string();

    let patch = Request::builder()
        .method("PATCH")
        .uri(format!("/api/items/{id}"))
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(json!({"done": true}).to_string()))
        .unwrap();
    let (status, updated) = send(router(state.clone()), patch).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated["done"], true);

    let del = Request::builder()
        .method("DELETE")
        .uri(format!("/api/items/{id}"))
        .body(Body::empty())
        .unwrap();
    let (status, _) = send(router(state.clone()), del).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) = send(router(state), get(&format!("/api/items/{id}"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
