use std::{
    collections::VecDeque,
    sync::{Arc, RwLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use serde::Serialize;

/// An explanation, in the shape `rn` uses for its info buttons.
///
/// The bar is the mechanism, not the label. "Shows memory usage" is a wasted
/// panel; "MemAvailable is what the kernel believes it could hand out without
/// swapping - most of 'used' is reclaimable page cache, so free memory looks
/// alarming and means little" is the bar.
///
/// These are `&'static str` on purpose: they are written next to the code that
/// produces the number, by the person who knows why it is computed that way.
#[derive(Debug, Clone, Serialize)]
pub struct Info {
    /// What this is, mechanically.
    pub what: &'static str,
    /// Why it matters - what decision it informs.
    pub why: &'static str,
    /// What a wrong or alarming value looks like, and what follows from it.
    pub if_wrong: &'static str,
}

/// Explanation for one field inside a panel's reading.
#[derive(Debug, Clone, Serialize)]
pub struct StatInfo {
    /// The key in the sample's JSON value.
    pub key: &'static str,
    #[serde(flatten)]
    pub info: Info,
}

/// Describes a panel to the UI. Everything the UI needs to render a tile
/// before it has any data - including how to explain it.
#[derive(Debug, Clone, Serialize)]
pub struct PanelMeta {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub interval_secs: u64,
    /// Which subject this panel belongs to.
    pub subject: Subject,
    /// The panel's own explanation.
    pub info: Info,
    /// One per top-level key the collector emits. A test enforces that none is
    /// missing - without it this decays the first time someone is in a hurry.
    pub stats: Vec<StatInfo>,
}

/// One observation. The payload is free-form JSON deliberately: adding a panel
/// must not mean touching a shared enum, a router, or the UI's type definitions.
#[derive(Debug, Clone, Serialize)]
pub struct Sample {
    /// Milliseconds since the Unix epoch.
    pub at: u64,
    pub value: serde_json::Value,
}

impl Sample {
    pub fn now(value: serde_json::Value) -> Self {
        let at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Self { at, value }
    }
}

/// Which of the three subjects a panel belongs to.
///
/// The engine owns this rather than the UI pattern-matching on panel ids:
/// adding a panel should not mean editing a list in QML.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Subject {
    NixOS,
    Qt,
    Rust,
}

/// How worried to be.
///
/// Computed by the collector, not the UI. The thresholds are judgement about
/// what the numbers mean - "available under 1 GB *and* non-zero stall" - and
/// that belongs next to the code that knows why the number is computed the way
/// it is. It also means the overview page can rank subjects without rendering
/// every panel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Ok,
    Warn,
    Bad,
    /// No reading, or the collector could not tell.
    Unknown,
}

/// A source of readings.
///
/// `sample` is synchronous and may block (it reads /proc or shells out); the
/// scheduler runs it on a blocking thread. It returns a Result so one broken
/// collector degrades its own panel instead of taking down the engine - see
/// `Panel::error`.
pub trait Collector: Send + Sync + 'static {
    fn meta(&self) -> PanelMeta;
    fn sample(&self) -> anyhow::Result<serde_json::Value>;

    /// Judge a reading: how worried to be, and the one line worth showing on
    /// an overview that does not render the panel.
    ///
    /// Implemented per collector rather than defaulted, so adding a panel
    /// forces a decision about what "bad" means for it. A panel with no
    /// opinion about its own values has not earned a place on the dashboard.
    fn status(&self, value: &serde_json::Value) -> (Status, String);
}

/// A collector plus its retained history.
pub struct Panel {
    pub meta: PanelMeta,
    collector: Arc<dyn Collector>,
    history: RwLock<VecDeque<Sample>>,
    /// Last error, if the most recent sample failed. Surfaced to the UI so a
    /// panel can show "broken" rather than silently showing stale data.
    error: RwLock<Option<String>>,
    capacity: usize,
}

impl Panel {
    pub fn new(collector: Arc<dyn Collector>, capacity: usize) -> Self {
        Self {
            meta: collector.meta(),
            collector,
            history: RwLock::new(VecDeque::with_capacity(capacity)),
            error: RwLock::new(None),
            capacity,
        }
    }

    pub fn interval(&self) -> Duration {
        Duration::from_secs(self.meta.interval_secs)
    }

    /// Take one reading and record it. Never panics on collector failure.
    pub fn tick(&self) {
        match self.collector.sample() {
            Ok(value) => {
                let mut history = self.history.write().expect("history lock poisoned");
                if history.len() == self.capacity {
                    history.pop_front();
                }
                history.push_back(Sample::now(value));
                *self.error.write().expect("error lock poisoned") = None;
            }
            Err(e) => {
                tracing::warn!(panel = self.meta.id, error = %e, "collector failed");
                *self.error.write().expect("error lock poisoned") = Some(e.to_string());
            }
        }
    }

    pub fn latest(&self) -> Option<Sample> {
        self.history.read().expect("history lock poisoned").back().cloned()
    }

    pub fn history(&self, limit: usize) -> Vec<Sample> {
        let history = self.history.read().expect("history lock poisoned");
        history.iter().rev().take(limit).rev().cloned().collect()
    }

    pub fn error(&self) -> Option<String> {
        self.error.read().expect("error lock poisoned").clone()
    }

    pub fn collector(&self) -> Arc<dyn Collector> {
        Arc::clone(&self.collector)
    }
}
