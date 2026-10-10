use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, Urgency};
use crate::{
    collector::{Collector, Subject},
    collectors::qt::QtCollector,
};

/// A Nix snippet for a Qt prefix that cxx-qt can actually use.
///
/// Offered only when a qmake exists but its prefix is missing host tools -
/// the state that builds happily until code generation. "No Qt here" is not
/// a problem to fix, so it produces no action.
pub struct QtPrefix;

const MERGED_PREFIX_SNIPPET: &str = r#"# One merged Qt prefix, in your flake's devShell.
#
# cxx-qt asks ONE qmake for headers, libs AND host tools, but nixpkgs splits
# those across store paths. qt6.env merges out+dev and copies a real qmake
# next to a generated qt.conf, so the merged prefix is what qmake reports.
# A plain symlinkJoin does NOT work: nixpkgs' qmake has its prefix baked in.
let
  qtEnv = pkgs.qt6.env "my-qt-env" (with pkgs.qt6; [
    qtdeclarative      # qmltyperegistrar, qmlcachegen live here, not qtbase
    qtsvg
    qtshadertools
  ]);
in
pkgs.mkShell {
  packages = [ qtEnv ];

  # Qt6Gui/Qt6OpenGL .prl files reference -lGLX and -lOpenGL. buildInputs,
  # not packages: only buildInputs feed the cc wrapper's NIX_LDFLAGS.
  buildInputs = [ pkgs.libglvnd ];

  QMAKE = "${qtEnv}/bin/qmake";
}"#;

impl ActionProvider for QtPrefix {
    fn id(&self) -> &'static str {
        "qt-prefix"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let v = QtCollector.sample()?;

        // No Qt at all is a legitimate state, not something to fix.
        let Some(version) = v["version"].as_str() else {
            return Ok(Vec::new());
        };
        if v["prefix_complete"].as_bool().unwrap_or(false) {
            return Ok(Vec::new());
        }

        let missing: Vec<String> = v["tools_missing"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|t| t.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();

        Ok(vec![Action {
            id: "qt-merged-prefix".into(),
            title: "Qt prefix is missing host tools".into(),
            subject: Subject::Qt,
            kind: ActionKind::Nix,
            why: format!(
                "qmake reports Qt {version}, but {} is not in its prefix. A \
                 cxx-qt build will fail during code generation.",
                missing.join(", ")
            ),
            info: ActionInfo {
                what: "Builds one Qt prefix containing qtbase and the modules \
                       whose host tools cxx-qt needs, and points QMAKE at it.",
                if_wrong: "Adding more entries to buildInputs will not help - \
                           qmake still reports only qtbase's prefix. The merge \
                           is the fix, not more inputs.",
            },
            command: MERGED_PREFIX_SNIPPET.into(),
            // A Nix snippet is configuration, not a command. There is
            // nothing to run: it goes in a file, and the rebuild applies it.
            run: None,
            effects: vec![
                "Changes only your dev shell; nothing system-wide".into(),
                "Re-enter the shell for QMAKE to take effect".into(),
            ],
            needs_root: false,
            urgency: Urgency::Advised,
        }])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silent_when_no_qt_present() {
        // The engine's own environment has no Qt, so this must produce
        // nothing rather than nagging about a problem that does not exist.
        let actions = QtPrefix.actions().unwrap();
        let v = QtCollector.sample().unwrap();
        if v["version"].as_str().is_none() {
            assert!(actions.is_empty(), "offered an action with no Qt present");
        }
    }
}
