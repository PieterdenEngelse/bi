use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;

/// Prove that privileged actions can actually run, without doing anything.
///
/// Every other elevated action changes the machine, which makes "does the Run
/// button work here?" a question you can only answer by accepting a
/// consequence. That is a bad place to find out that no polkit agent is
/// running, or that the unit was hardened in a way that blocks pkexec - the
/// moment you need `nixos-rebuild switch` is not the moment to discover it.
///
/// So: one action whose entire effect is the prompt. It elevates and runs
/// `true`. Success means escalation works end to end; the failure modes are
/// the interesting part, and `runner` already translates them (126 = dismissed
/// or no agent, 127 = pkexec could not run at all).
///
/// This is the same question the Qt and Rust panels ask - "will this work in
/// this environment?" - applied to the engine's own ability to act.
pub struct EscalationSelfTest;

impl ActionProvider for EscalationSelfTest {
    fn id(&self) -> &'static str {
        "escalation-self-test"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        // pkexec is the mechanism; with no pkexec at all there is nothing to
        // test and the action would only be noise.
        let has_pkexec = [
            "/run/wrappers/bin/pkexec",
            "/run/current-system/sw/bin/pkexec",
        ]
        .iter()
        .any(|p| std::path::Path::new(p).exists());
        if !has_pkexec {
            return Ok(Vec::new());
        }

        Ok(vec![Action {
            id: "check-escalation".into(),
            title: "Check that privileged actions can run".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: "Everything else that needs root also changes something. This \
                  asks for the same authorisation and then does nothing, so you \
                  can confirm the prompt works before you need it."
                .into(),
            info: ActionInfo {
                what: "Runs `true` - a program whose only job is to succeed - \
                       through pkexec. The authentication prompt is the whole \
                       test: if it appears and you authorise it, every other \
                       privileged action can run too.",
                if_wrong: "'not authorised' means the prompt was dismissed, or \
                           no polkit agent is running in this session to show \
                           it. 'pkexec could not run the command' usually means \
                           the service is still sandboxed - NoNewPrivileges \
                           stops setuid taking effect, and nothing else will \
                           escalate either.",
            },
            command: "pkexec true   # succeeds silently; the prompt is the point".into(),
            run: Some(RunCommand {
                program: "true".into(),
                args: vec![],
                elevate: true,
                cwd: None,
            }),
            effects: vec!["Nothing. It exists to prove the prompt works.".into()],
            needs_root: true,
            urgency: Urgency::Routine,
        }])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_self_test_changes_nothing() {
        let actions = EscalationSelfTest.actions().unwrap();
        let Some(a) = actions.first() else {
            return; // no pkexec on this machine
        };
        let run = a
            .run
            .as_ref()
            .expect("must be runnable - that is the point");

        assert!(
            run.elevate,
            "a test of escalation that does not elevate is not one"
        );
        assert!(
            run.args.is_empty(),
            "arguments would make it do something; it must not"
        );
        // Pinned deliberately: the value of this action is that running it is
        // free. Anything with an effect belongs in its own provider.
        assert_eq!(run.program, "true");
    }
}
