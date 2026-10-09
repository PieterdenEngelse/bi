use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;
use crate::collectors::failed_units::{failed_units, Scope};

/// One restart action per failed unit.
///
/// Note the asymmetry this makes visible: a *user* unit you can restart
/// yourself, a *system* unit needs root. The generated command differs
/// accordingly, and `needs_root` says which is which.
pub struct FailedUnits;

impl ActionProvider for FailedUnits {
    fn id(&self) -> &'static str {
        "failed-units"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let (units, _unavailable) = failed_units();

        Ok(units
            .into_iter()
            .map(|u| {
                let user_scope = u.scope == Scope::User;
                let flag = if user_scope { "--user " } else { "" };
                Action {
                    id: format!("restart-{}-{}", u.scope.as_str(), u.unit),
                    title: format!("Restart {}", u.unit),
                    subject: Subject::NixOS,
                    kind: ActionKind::Shell,
                    why: format!(
                        "{} unit is in a failed state{}.",
                        if user_scope { "This user" } else { "This system" },
                        if u.description.is_empty() {
                            String::new()
                        } else {
                            format!(" ({})", u.description)
                        }
                    ),
                    info: ActionInfo {
                        what: "Stops the unit and starts it again. The status \
                               command above is listed first because a restart \
                               discards the failure output that explains why it \
                               stopped.",
                        if_wrong: "A unit that fails again immediately was \
                                   failing at start, not crashing - restarting \
                                   it repeatedly will not help. Read its \
                                   journal instead.",
                    },
                    command: format!(
                        "{}systemctl {}status {}   # inspect first\n{}systemctl {}restart {}",
                        if user_scope { "" } else { "sudo " },
                        flag,
                        u.unit,
                        if user_scope { "" } else { "sudo " },
                        flag,
                        u.unit
                    ),
                    // Only the restart, never the `status` line the display
                    // text leads with. Note the asymmetry carried through:
                    // a user unit is yours to restart, a system unit prompts.
                    run: Some(RunCommand {
                        program: "systemctl".into(),
                        args: if user_scope {
                            vec!["--user".into(), "restart".into(), u.unit.clone()]
                        } else {
                            vec!["restart".into(), u.unit.clone()]
                        },
                        elevate: !user_scope,
                    }),
                    effects: vec![
                        format!("Restarts {} and anything bound to it", u.unit),
                        "Does not fix the underlying cause - read the status first".into(),
                    ],
                    needs_root: !user_scope,
                    urgency: Urgency::Needed,
                }
            })
            .collect())
    }
}
