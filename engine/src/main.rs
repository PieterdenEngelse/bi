use std::net::SocketAddr;

use nixdash_engine::{router, Registry};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "nixdash_engine=info,tower_http=warn".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let registry = Registry::with_default_collectors();

    // Sample once up front so the API is useful immediately rather than
    // returning empty panels for the first interval.
    {
        let r = registry.clone();
        tokio::task::spawn_blocking(move || r.tick_all()).await?;
    }
    registry.spawn_pollers();

    let port: u16 = std::env::var("NIXDASH_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3100);

    // Loopback only, deliberately and not configurably. Reaching this from
    // another machine would need auth and TLS, which this does not have.
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("nixdash engine listening on http://{addr}");

    axum::serve(listener, router(registry)).await?;
    Ok(())
}
