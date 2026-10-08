# b1

A small JSON HTTP backend in Rust, built on [axum](https://github.com/tokio-rs/axum).

```sh
nix develop      # rustc/cargo/clippy + curl + jq
cargo run        # http://127.0.0.1:3000   (override with PORT)
cargo test
```

`nix build` produces a standalone binary at `./result/bin/b1`.

## Endpoints

| Method | Path | Behaviour |
|---|---|---|
| GET | `/health` | `{"status":"ok","version":"0.1.0"}` |
| GET | `/api/items` | list, sorted by name |
| POST | `/api/items` | `{"name":"..."}` → 201 + the item |
| GET | `/api/items/{id}` | one item, or 404 |
| PATCH | `/api/items/{id}` | `{"done":true}` → updated item |
| DELETE | `/api/items/{id}` | 204, or 404 |

```sh
curl -s localhost:3000/api/items -H 'content-type: application/json' \
     -d '{"name":"first task"}' | jq
```

Errors are uniform: a non-2xx carries `{"error":"..."}`.

## Layout

| File | Role |
|---|---|
| `src/main.rs` | binary: logging, port, serve |
| `src/lib.rs` | library root, so tests can build the router directly |
| `src/routes/mod.rs` | route table + middleware |
| `src/routes/items.rs` | handlers |
| `src/state.rs` | `AppState` + the storage behind it |
| `src/error.rs` | `AppError` → HTTP status + JSON body |
| `tests/api.rs` | integration tests against the real router |

The split between `main.rs` and `lib.rs` is deliberate: tests call
`router(AppState::new())` and drive it with `tower::ServiceExt::oneshot`, so
they exercise real routing, extractors and status codes without binding a port.

## Storage

**In-memory** (`HashMap` behind an `RwLock`) — state is lost on restart. This
keeps the project runnable with no database to provision.

Handlers never touch the map directly; they only call `AppState` methods
(`list`, `get`, `create`, `set_done`, `delete`). Swapping in Postgres via
`sqlx` means reimplementing those five methods and making them `async` — the
handlers barely change.

## Notes

- axum **0.8** changed path parameter syntax from `:id` to `{id}`. Most
  tutorials online still show the old form, which silently fails to match.
- CORS is `permissive` for local development. Restrict it before exposing this
  anywhere real.
- `PORT` is read from the environment; it binds `127.0.0.1`, not `0.0.0.0`.
