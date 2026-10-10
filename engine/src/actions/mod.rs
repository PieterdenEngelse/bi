//! Suggested actions, and executing them.
//!
//! The engine itself holds no privilege: it runs as you, and nothing here is
//! setuid. Actions that need root are executed via `pkexec`, which hands the
//! decision to polkit - **the prompt is the authorisation**, not the engine.
//!
//! Two consequences worth keeping in mind:
//!
//! - The API is unauthenticated and bound to loopback. Anything that can reach
//!   :3100 can ask the engine to start a privileged action. The polkit prompt
//!   is the only thing between that and a rebuild.
//! - What runs is `RunCommand`, an explicit program and argument list - never
//!   the displayed text, which is prose for a human and would execute its own
//!   commentary.

pub mod drift;
pub mod escalation;
pub mod gc;
pub mod qt;
pub mod reboot;
pub mod runner;
pub mod rust;
pub mod settings;
pub mod units;
pub mod wasm;

use std::sync::Arc;

use serde::Serialize;

use crate::collector::Subject;

/// What kind of thing the command is, so the UI can label it honestly.
///
/// A shell command you run now; a Nix snippet you paste into a file and then
/// rebuild. Telling someone to "run" a flake fragment would be nonsense, and
/// the distinction is the whole reason the Config page exists separately.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ActionKind {
    /// Paste into a terminal.
    Shell,
    /// Paste into a Nix file, then rebuild.
    Nix,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Urgency {
    /// Routine maintenance; offer it, do not nag.
    Routine,
    /// Something is drifting; worth doing soon.
    Advised,
    /// Something is wrong now.
    Needed,
}

/// The static half of an action's explanation.
///
/// Deliberately smaller than a panel's `Info`: an action already carries a
/// runtime `why` ("booted and current differ, here are the two paths"), so
/// repeating a static `why` here would be duplication. What is missing from a
/// bare command is the *mechanism* and the *risk*, and those are static.
#[derive(Debug, Clone, Serialize)]
pub struct ActionInfo {
    /// What the command actually does, mechanically.
    pub what: &'static str,
    /// What goes wrong if it is run at the wrong moment, or misunderstood.
    pub if_wrong: &'static str,
}

/// How to actually execute an action, as an explicit program plus arguments.
///
/// Deliberately NOT parsed from the displayed `command`: that text is written
/// for a human - it carries comments, alternatives, and a leading dry-run that
/// must not be conflated with the real thing. Running it verbatim would
/// execute every line, including the one the comment says to consider first.
///
/// `None` means the action cannot be executed: a Nix snippet is configuration,
/// not a command, and there is nothing sensible to run.
#[derive(Debug, Clone, Serialize)]
pub struct RunCommand {
    pub program: String,
    pub args: Vec<String>,
    /// Run it under pkexec. The engine holds no privilege of its own; this
    /// asks polkit, which prompts you, and the prompt is the authorisation.
    pub elevate: bool,
    /// Directory to run in. `None` means the service's own, which is not a
    /// meaningful location - anything operating on a project must say where.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Action {
    pub id: String,
    pub title: String,
    /// Which subject this belongs to, so the UI can group it.
    pub subject: Subject,
    /// Shell command, or Nix snippet.
    pub kind: ActionKind,
    /// Why this is being offered *now*, in plain language, including the
    /// runtime detail that triggered it. An action with no honest answer here
    /// should not exist.
    pub why: String,
    /// Mechanism and risk - the part a command line does not tell you.
    pub info: ActionInfo,
    /// The exact command, as shown to you. May be multi-line, commented, and
    /// may describe alternatives - it is for reading, not for execution.
    pub command: String,
    /// What the Run button executes, if anything. See RunCommand.
    pub run: Option<RunCommand>,
    /// What it changes, so consequences are visible before running it.
    pub effects: Vec<String>,
    /// Whether it needs root. Mirrors `run.elevate` for display.
    pub needs_root: bool,
    pub urgency: Urgency,
}

/// Inspects system state and yields the actions that currently make sense.
///
/// Providers must be cheap and read-only: they run on every `GET /api/actions`.
/// Anything slow (store size, network) belongs behind a cached collector.
pub trait ActionProvider: Send + Sync + 'static {
    fn id(&self) -> &'static str;
    fn actions(&self) -> anyhow::Result<Vec<Action>>;
}

#[derive(Clone)]
pub struct Actions {
    providers: Arc<Vec<Arc<dyn ActionProvider>>>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ActionsReport {
    pub actions: Vec<Action>,
    /// Providers that failed, so a broken probe is visible rather than
    /// silently reducing the list.
    pub errors: Vec<ProviderError>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProviderError {
    pub provider: String,
    pub error: String,
}

impl Actions {
    pub fn with_defaults() -> Self {
        Self::new(vec![
            Arc::new(reboot::RebootNeeded) as Arc<dyn ActionProvider>,
            Arc::new(drift::ConfigDrift),
            Arc::new(units::FailedUnits),
            Arc::new(gc::GarbageCollect),
            Arc::new(qt::QtPrefix),
            Arc::new(rust::RustTargets),
            Arc::new(escalation::EscalationSelfTest),
            Arc::new(wasm::WasmStale),
            Arc::new(settings::UnappliedSettings),
        ])
    }

    pub fn new(providers: Vec<Arc<dyn ActionProvider>>) -> Self {
        Self {
            providers: Arc::new(providers),
        }
    }

    pub fn report(&self) -> ActionsReport {
        let mut actions = Vec::new();
        let mut errors = Vec::new();

        for p in self.providers.iter() {
            match p.actions() {
                Ok(found) => actions.extend(found),
                Err(e) => errors.push(ProviderError {
                    provider: p.id().to_string(),
                    error: e.to_string(),
                }),
            }
        }

        // Most urgent first; routine maintenance should never push a real
        // problem down the list.
        actions.sort_by_key(|a| match a.urgency {
            Urgency::Needed => 0,
            Urgency::Advised => 1,
            Urgency::Routine => 2,
        });

        ActionsReport { actions, errors }
    }
}
