use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;

/// Store garbage collection.
///
/// Offered always, at Routine urgency - the engine deliberately does NOT
/// compute the reclaimable size. `nix-collect-garbage --dry-run` walks the
/// store and takes seconds to minutes; running it on every request would make
/// a monitoring tool a source of load, which is self-defeating. The dry-run is
/// instead part of the command the user pastes, so they see the estimate at
/// the moment they are deciding.
pub struct GarbageCollect;

impl ActionProvider for GarbageCollect {
    fn id(&self) -> &'static str {
        "gc"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        if !std::path::Path::new("/nix/store").is_dir() {
            return Ok(Vec::new());
        }

        Ok(vec![Action {
            id: "gc-store".into(),
            title: "Collect garbage in the Nix store".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: "Old generations and unreferenced paths accumulate. Run the \
                  dry-run first to see what would be freed."
                .into(),
            info: ActionInfo {
                what: "Deletes store paths nothing references any more. With \
                       -d it also deletes every old generation first, which is \
                       what makes their contents unreferenced.",
                if_wrong: "-d removes your rollback targets. Generations \
                           sharing a nixpkgs revision cost almost nothing, so \
                           most of what -d frees is build output you would \
                           free anyway - run the dry-run and look before \
                           deciding it is worth losing them.",
            },
            command: "nix-collect-garbage --dry-run\n# then, to actually delete:\n\
                      sudo nix-collect-garbage -d"
                .into(),
            // The sharpest example of why `command` is not executable. It
            // contains a dry-run, a comment, and the real deletion. Running
            // that text would do the survey and then delete anyway, having
            // shown nobody the survey. Run is the deletion alone, named
            // explicitly, with the dry-run left as something you choose.
            run: Some(RunCommand {
                program: "nix-collect-garbage".into(),
                args: vec!["-d".into()],
                elevate: true,
            }),
            effects: vec![
                "-d deletes ALL old generations - rollback targets disappear".into(),
                "Anything not reachable from a gcroot is removed".into(),
                "Next rebuild may re-download what was deleted".into(),
            ],
            needs_root: true,
            urgency: Urgency::Routine,
        }])
    }
}
