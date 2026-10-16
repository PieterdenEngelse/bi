use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, Urgency};
use crate::{
    collector::{Collector, Subject},
    collectors::rust::{rust_src, which, RustCollector},
};

/// Nix snippets for Rust targets that are absent.
///
/// Both of these are things a version number cannot tell you and the error
/// message points away from: a missing target std reads as "can't find crate
/// for std", and a missing lld reads as a linker problem rather than a
/// toolchain one.
pub struct RustTargets;

const FENIX_SNIPPET: &str = r#"# A Rust toolchain with the Emscripten target, in your flake.
#
# nixpkgs' rustc ships std for the host only, so a cross build fails with
# "can't find crate for `std`". fenix packages upstream Rust's per-target
# std, which keeps the whole toolchain inside Nix - no rustup, which fights
# Nix for control of ~/.rustup and PATH.

inputs.fenix = {
  url = "github:nix-community/fenix";
  # fenix's rust-std comes from upstream Rust release artifacts, not from
  # nixpkgs, so following avoids a second nixpkgs in the lock for nothing.
  inputs.nixpkgs.follows = "nixpkgs";
};

# ...then in the devShell:
let
  rustToolchain = fenix.packages.${system}.combine (with fenix.packages.${system}; [
    stable.rustc
    stable.cargo
    targets."wasm32-unknown-emscripten".stable.rust-std
  ]);
in
pkgs.mkShell {
  packages = [ rustToolchain ];
}"#;

const RUST_SRC_SNIPPET: &str = r#"# Standard library sources, so rust-analyzer can resolve std.
#
# Installing rustc does NOT install these. rust-analyzer needs the source
# text, not the compiled std it already has, and without it every std type
# shows as unresolved while the LSP otherwise runs normally.
#
# System-wide, in /etc/nixos/configuration.nix - next to rustc:

  environment.systemPackages = with pkgs; [
    rustc
    cargo
    rust-analyzer
    rustPlatform.rustLibSrc        # <- the sources
  ];

  environment.variables.RUST_SRC_PATH =
    "${pkgs.rustPlatform.rustLibSrc}";

# Or per-project, in a devShell - which is better if different projects
# pin different toolchains:

  devShells.default = pkgs.mkShell {
    packages = with pkgs; [ rustc cargo rust-analyzer ];
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

# With a fenix toolchain, ask for the component instead and it comes with
# RUST_SRC_PATH already correct:
#
#   fenix.packages.${system}.stable.withComponents [
#     "cargo" "rustc" "rust-src" "rust-analyzer"
#   ]
"#;

const LLD_SNIPPET: &str = r#"# lld, for wasm32-unknown-unknown.
#
# That target links with lld. Without it the build fails with
#   error: linker `lld` not found
# which names the linker rather than the target, sending you to look in the
# wrong place entirely. One package, not a toolchain change.

pkgs.mkShell {
  packages = [ pkgs.lld ];
}"#;

impl ActionProvider for RustTargets {
    fn id(&self) -> &'static str {
        "rust-targets"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let v = RustCollector.sample()?;

        // No Rust at all is not a problem to fix.
        let Some(rustc) = v["rustc"].as_str() else {
            return Ok(Vec::new());
        };
        let version = rustc.split_whitespace().nth(1).unwrap_or(rustc);

        let has_em = v["has_wasm32_emscripten"].as_bool().unwrap_or(false);
        let has_wasm = v["has_wasm32_unknown"].as_bool().unwrap_or(false);
        let has_lld = v["lld_available"].as_bool().unwrap_or(false);

        let mut out = Vec::new();

        if !has_em {
            out.push(Action {
                id: "rust-emscripten-target".into(),
                title: "No Emscripten target in the rustc on PATH".into(),
                subject: Subject::Rust,
                kind: ActionKind::Nix,
                // Scoped to the rustc that was actually looked at. This said
                // "a Qt for WebAssembly build cannot compile", which is a
                // claim about every environment on the machine from a probe
                // of exactly one - and it was wrong here, where the browser
                // UI builds in a dev shell carrying its own toolchain.
                why: format!(
                    "The rustc on PATH is {version}, which ships std for the \
                     host only - it has no wasm32-unknown-emscripten. A Qt \
                     for WebAssembly build started from this environment \
                     would fail with \"can't find crate for `std`\"."
                ),
                info: ActionInfo {
                    what: "Adds a fenix toolchain carrying the Emscripten \
                           target's standard library to the dev shell.",
                    if_wrong: "A dev shell that brings its own Rust \
                               toolchain is a different environment and is \
                               not what was measured here, so this can be \
                               true while that build works perfectly - \
                               nixdash's own browser UI is built that way, \
                               in `nix develop .#wasm`, which already \
                               supplies this target. Only needed if you are \
                               building for Qt WebAssembly at all: plain \
                               browser wasm uses wasm32-unknown-unknown, \
                               which nixpkgs already ships - that one needs \
                               lld instead.",
                },
                command: FENIX_SNIPPET.into(),
                run: None, // Nix snippet - paste and rebuild, nothing to execute.
                effects: vec![
                    "Changes only your dev shell".into(),
                    "Adds a flake input and downloads a second toolchain".into(),
                ],
                needs_root: false,
                urgency: Urgency::Routine,
            });
        }

        // Only worth raising alongside the target that actually links with it.
        if has_wasm && !has_lld {
            out.push(Action {
                id: "rust-lld".into(),
                title: "wasm32-unknown-unknown is installed but lld is not".into(),
                subject: Subject::Rust,
                kind: ActionKind::Nix,
                why: "That target links with lld, which is not on PATH. The \
                      build will fail at link time."
                    .into(),
                info: ActionInfo {
                    what: "Adds the lld linker to the dev shell.",
                    if_wrong: "The error names the linker, not the target, so \
                               it reads like a toolchain problem. It is one \
                               missing package.",
                },
                command: LLD_SNIPPET.into(),
                run: None, // Nix snippet - paste and rebuild, nothing to execute.
                effects: vec!["Changes only your dev shell".into()],
                needs_root: false,
                urgency: Urgency::Routine,
            });
        }

        // rust-analyzer present but unable to resolve std. Raised only when
        // rust-analyzer is actually installed: the sources are useless on
        // their own, and suggesting them to someone with no LSP would be
        // noise about a component they have no use for.
        if which("rust-analyzer").is_some() && rust_src().is_none() {
            out.push(Action {
                id: "rust-src-missing".into(),
                title: "rust-analyzer cannot resolve the standard library".into(),
                subject: Subject::Rust,
                kind: ActionKind::Nix,
                why: "rust-analyzer is installed, but the standard library \
                      SOURCES are not. Every Vec, String and Option will show \
                      as unresolved in your editor while rust-analyzer itself \
                      runs perfectly."
                    .into(),
                info: ActionInfo {
                    what: "Adds the standard library sources - the rust-src \
                           component - and points RUST_SRC_PATH at them. \
                           rust-analyzer reads these to resolve std; the \
                           compiled standard library it already has is not \
                           enough, because the IDE needs the source text.",
                    if_wrong: "This is easy to live with for a long time \
                               without diagnosing, because nothing fails: \
                               the LSP starts, runs, and simply reports std \
                               types as unknown. It reads as 'rust-analyzer \
                               is broken on NixOS' rather than as one missing \
                               package.",
                },
                command: RUST_SRC_SNIPPET.into(),
                run: None, // Nix snippet - paste and rebuild, nothing to run.
                effects: vec![
                    "Adds the rust-src component and sets RUST_SRC_PATH".into(),
                    "Affects your editor only - no build behaviour changes".into(),
                ],
                needs_root: false,
                urgency: Urgency::Advised,
            });
        }

        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offers_only_what_is_actually_missing() {
        let v = RustCollector.sample().unwrap();
        let actions = RustTargets.actions().unwrap();

        let has_em = v["has_wasm32_emscripten"].as_bool().unwrap_or(false);
        let offered_em = actions.iter().any(|a| a.id == "rust-emscripten-target");
        assert_eq!(
            offered_em, !has_em,
            "emscripten action offered when the target is present, or vice versa"
        );
    }

    #[test]
    fn lld_action_requires_the_target_that_needs_it() {
        // lld alone is not a problem; it only matters with
        // wasm32-unknown-unknown installed.
        let v = RustCollector.sample().unwrap();
        let actions = RustTargets.actions().unwrap();
        let offered = actions.iter().any(|a| a.id == "rust-lld");
        let expect = v["has_wasm32_unknown"].as_bool().unwrap_or(false)
            && !v["lld_available"].as_bool().unwrap_or(false);
        assert_eq!(offered, expect);
    }
}
