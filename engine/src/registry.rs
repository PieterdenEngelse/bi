use std::{collections::BTreeMap, sync::Arc};

use serde::Serialize;

use crate::{
    collector::{Collector, Panel, PanelMeta, Sample, Status},
    collectors::{
        disk::DiskCollector, failed_units::FailedUnitsCollector, generations::GenerationsCollector,
        memory::MemoryCollector, qt::QtCollector, qt_runtime::QtRuntimeCollector,
        qt_wasm::QtWasmCollector, rust::RustCollector, rust_build::RustBuildCollector,
    },
};

/// How many samples each panel retains. At the memory panel's 2s interval
/// this is ~30 minutes of history, which is enough to see a build ramp up.
const HISTORY: usize = 900;

#[derive(Debug, Clone, Serialize)]
pub struct PanelSummary {
    #[serde(flatten)]
    pub meta: PanelMeta,
    pub latest: Option<Sample>,
    /// Present when the most recent sample failed; the panel is stale.
    pub error: Option<String>,
    /// The collector's own judgement of the latest reading. Computed here so
    /// the overview can rank subjects without rendering a single panel.
    pub status: Status,
    /// One line worth showing when the panel itself is not on screen.
    pub headline: String,
}

#[derive(Clone)]
pub struct Registry {
    panels: Arc<BTreeMap<&'static str, Arc<Panel>>>,
}

impl Registry {
    /// The set of panels the engine ships with.
    pub fn with_default_collectors() -> Self {
        Self::from_collectors(vec![
            Arc::new(MemoryCollector) as Arc<dyn Collector>,
            Arc::new(FailedUnitsCollector),
            Arc::new(GenerationsCollector),
            Arc::new(DiskCollector),
            Arc::new(QtCollector),
            Arc::new(QtRuntimeCollector),
            Arc::new(QtWasmCollector),
            Arc::new(RustCollector),
            Arc::new(RustBuildCollector),
        ])
    }

    pub fn from_collectors(collectors: Vec<Arc<dyn Collector>>) -> Self {
        let panels = collectors
            .into_iter()
            .map(|c| {
                let panel = Arc::new(Panel::new(c, HISTORY));
                (panel.meta.id, panel)
            })
            .collect();
        Self {
            panels: Arc::new(panels),
        }
    }

    pub fn get(&self, id: &str) -> Option<Arc<Panel>> {
        self.panels.get(id).cloned()
    }

    pub fn all(&self) -> Vec<Arc<Panel>> {
        self.panels.values().cloned().collect()
    }

    pub fn summaries(&self) -> Vec<PanelSummary> {
        self.all()
            .into_iter()
            .map(|p| {
                let latest = p.latest();
                let error = p.error();

                // No reading yet, or the collector failed: Unknown, not Ok.
                // Defaulting to Ok would make a broken panel look healthy,
                // which is the one thing a monitor must never do.
                let (status, headline) = match (&latest, &error) {
                    (_, Some(e)) => (Status::Unknown, e.clone()),
                    (Some(s), None) => p.collector().status(&s.value),
                    (None, None) => (Status::Unknown, "no reading yet".to_string()),
                };

                PanelSummary {
                    meta: p.meta.clone(),
                    latest,
                    error,
                    status,
                    headline,
                }
            })
            .collect()
    }

    /// Sample every panel once. Used at startup so the API is never empty,
    /// and by tests.
    pub fn tick_all(&self) {
        for panel in self.all() {
            panel.tick();
        }
    }

    /// Spawn one task per panel, each on its own interval.
    ///
    /// Panels poll independently on purpose: memory wants 2s, shelling out to
    /// systemctl at 2s would be wasteful, and later panels (store size) are
    /// far slower still.
    pub fn spawn_pollers(&self) {
        for panel in self.all() {
            let panel = Arc::clone(&panel);
            tokio::spawn(async move {
                let mut ticker = tokio::time::interval(panel.interval());
                ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                loop {
                    ticker.tick().await;
                    let p = Arc::clone(&panel);
                    // sample() may block (reads /proc, spawns systemctl).
                    let _ = tokio::task::spawn_blocking(move || p.tick()).await;
                }
            });
        }
    }
}
