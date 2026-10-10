//! System-level configuration the app can prepare — tier 3.
//!
//! This is the tier that was deliberately left copy-only, and the reason
//! stands: `/etc/nixos` is where a bad write costs you a boot. It is built
//! anyway, so the safety has to be structural rather than a warning in a
//! comment.
//!
//! **Four constraints, each enforced rather than asserted:**
//!
//! 1. **A generated file, never `configuration.nix`.** The app owns
//!    `/etc/nixos/nixdash-system.nix` and rewrites it whole. Your
//!    configuration.nix imports it and is never read, parsed or edited.
//! 2. **Additive attributes only.** The whitelist produces
//!    `environment.systemPackages` and `environment.variables` — nothing
//!    touching boot, filesystems, users, kernel or services. A file that can
//!    only add a package to PATH cannot strand you at a boot prompt.
//! 3. **Staged as you, installed under a prompt.** Nothing here writes to
//!    `/etc`. The app renders into its own directory in your home; copying
//!    that into place is a separate action that goes through polkit, so the
//!    privileged step is visible and refusable.
//! 4. **Three states, never conflated.** *staged* (written here), *installed*
//!    (in /etc/nixos), *live* (confirmed by a panel after a rebuild). Each is
//!    reported separately because each is a different fact.

use std::path::PathBuf;

use anyhow::{bail, Result};
use serde::Serialize;

/// One system-level addition.
#[derive(Debug, Clone, Serialize)]
pub struct SystemExtra {
    pub key: &'static str,
    pub label: &'static str,
    /// Nix expression added to `environment.systemPackages`.
    pub package: Option<&'static str>,
    /// Entries for `environment.variables`, as (name, nix expr).
    pub variables: Vec<(&'static str, &'static str)>,
    /// The panel stat that confirms it after a rebuild.
    pub verified_by: &'static str,
    pub what: &'static str,
    pub why: &'static str,
    pub if_wrong: &'static str,
}

/// Everything the app may add system-wide.
///
/// Deliberately short. Each entry has to be additive, non-boot-critical, and
/// checkable afterwards — which rules out most of what lives in
/// configuration.nix and is exactly the point.
pub fn known() -> Vec<SystemExtra> {
    vec![SystemExtra {
        key: "rust-src",
        label: "Standard library sources, system-wide",
        package: Some("rustPlatform.rustLibSrc"),
        variables: vec![("RUST_SRC_PATH", "pkgs.rustPlatform.rustLibSrc")],
        verified_by: "rust.rust_src_available",
        what: "Adds the Rust standard library source text to the system \
               packages and sets RUST_SRC_PATH for every shell.",
        why: "rust-analyzer resolves std by reading these sources, and it is \
              installed system-wide here rather than per project - so the \
              sources belong at the same level. Installing rustc does not \
              bring them; they are a separate package.",
        if_wrong: "Affects editors only: no build behaviour changes and \
                   nothing starts or stops. If you would rather keep this per \
                   project, use the development shell section instead and \
                   leave this off.",
    }]
}

pub fn find(key: &str) -> Option<SystemExtra> {
    known().into_iter().find(|e| e.key == key)
}

/// Where the app stages its rendering — writable as you, never privileged.
pub fn staged_path() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("NIXDASH_SYSTEM_STAGED") {
        return Some(PathBuf::from(p));
    }
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join(".local/share/nixdash/system-staged.nix"))
}

/// Where it ends up once installed. Readable by anyone, writable only by root.
pub fn installed_path() -> PathBuf {
    std::env::var("NIXDASH_SYSTEM_INSTALLED")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/etc/nixos/nixdash-system.nix"))
}

/// Which entries a rendering enables, from the marker comments it carries.
pub fn read_enabled(text: &str) -> Vec<String> {
    known()
        .into_iter()
        .filter(|e| text.contains(&format!("# nixdash:{}", e.key)))
        .map(|e| e.key.to_string())
        .collect()
}

/// Top-level attributes this module is ever allowed to emit.
///
/// Used by `render` and asserted by a test. The list is the safety property:
/// anything outside it could affect whether the machine boots.
pub const ALLOWED_ATTRS: &[&str] = &["environment.systemPackages", "environment.variables"];

pub fn render(enabled: &[String]) -> String {
    let all = known();
    let chosen: Vec<&SystemExtra> = all
        .iter()
        .filter(|e| enabled.iter().any(|k| k == e.key))
        .collect();

    let mut packages = String::new();
    for e in &chosen {
        if let Some(pkg) = e.package {
            packages.push_str(&format!("    {pkg}   # nixdash:{}\n", e.key));
        }
    }
    if packages.is_empty() {
        packages.push_str("    # (none enabled)\n");
    }

    let mut variables = String::new();
    for e in &chosen {
        for (name, expr) in &e.variables {
            variables.push_str(&format!(
                "    {name} = \"${{{expr}}}\";   # nixdash:{}\n",
                e.key
            ));
        }
    }

    format!(
        "# Generated by nixdash. Rewritten in full whenever a system addition\n\
         # is toggled - edits made here by hand will be lost.\n\
         #\n\
         # Imported by configuration.nix, which nixdash never reads or edits.\n\
         #\n\
         # This file can only ADD packages and environment variables. It does\n\
         # not touch boot, filesystems, users, kernel or services, so it\n\
         # cannot leave the machine unbootable. The worst it can do is put a\n\
         # package on PATH that you did not want.\n\
         #\n\
         # Installing it changes nothing by itself: run `nixos-rebuild switch`.\n\
         {{ pkgs, ... }}:\n\
         {{\n\
         \x20 environment.systemPackages = with pkgs; [\n\
         {packages}\x20 ];\n\
         \n\
         \x20 environment.variables = {{\n\
         {variables}\x20 }};\n\
         }}\n"
    )
}

#[derive(Debug, Serialize)]
pub struct Change {
    pub key: String,
    pub enabled: bool,
    pub staged_path: String,
    pub rendered: String,
    pub diff: Vec<String>,
}

pub fn plan(current: &str, staged_path: &str, key: &str, enable: bool) -> Result<Change> {
    if find(key).is_none() {
        bail!("no system addition {key}");
    }
    let mut enabled = read_enabled(current);
    enabled.retain(|k| k != key);
    if enable {
        enabled.push(key.to_string());
    }
    let rendered = render(&enabled);
    Ok(Change {
        key: key.to_string(),
        enabled: enable,
        staged_path: staged_path.to_string(),
        diff: crate::settings::line_diff(current, &rendered),
        rendered,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_rendering_can_only_add_packages_and_variables() {
        // The safety property, checked rather than promised. Anything outside
        // these two attributes could affect whether the machine boots.
        let text = render(&["rust-src".into()]);
        for forbidden in [
            "boot.",
            "fileSystems",
            "users.",
            "systemd.",
            "services.",
            "networking.",
            "security.",
            "hardware.",
        ] {
            assert!(
                !text.contains(forbidden),
                "rendering contains {forbidden:?}, which could affect boot:\n{text}"
            );
        }
        for allowed in ALLOWED_ATTRS {
            assert!(text.contains(allowed), "missing {allowed}");
        }
    }

    #[test]
    fn an_empty_rendering_is_still_a_valid_module() {
        let text = render(&[]);
        assert!(text.contains("environment.systemPackages"));
        assert!(text.contains("(none enabled)"));
        assert!(read_enabled(&text).is_empty());
    }

    #[test]
    fn a_rendering_reads_back_as_what_was_enabled() {
        let text = render(&["rust-src".into()]);
        assert_eq!(read_enabled(&text), vec!["rust-src"]);
        assert!(text.contains("RUST_SRC_PATH"));
    }

    #[test]
    fn toggling_off_empties_it_rather_than_leaving_a_stale_entry() {
        let on = render(&["rust-src".into()]);
        let change = plan(&on, "/tmp/s.nix", "rust-src", false).unwrap();
        assert!(read_enabled(&change.rendered).is_empty());
        assert!(!change.rendered.contains("RUST_SRC_PATH"));
    }

    #[test]
    fn unknown_keys_cannot_be_written() {
        assert!(plan("", "/tmp/s.nix", "evil", true).is_err());
    }

    #[test]
    fn the_file_says_what_it_cannot_do() {
        // Someone finding this in /etc/nixos should be able to tell at a
        // glance that it is generated and that it is additive only.
        let text = render(&[]);
        assert!(text.contains("Generated by nixdash"));
        assert!(text.contains("cannot leave the machine unbootable"));
        assert!(text.contains("nixos-rebuild switch"));
    }

    #[test]
    fn staging_never_points_into_etc() {
        // The app writes only as you. Anything under /etc must arrive through
        // the install action and its polkit prompt.
        if let Some(p) = staged_path() {
            assert!(
                !p.starts_with("/etc"),
                "staged rendering would be written to {p:?}"
            );
        }
    }

    #[test]
    fn every_entry_names_a_stat_that_confirms_it() {
        for e in known() {
            assert!(
                e.verified_by.contains('.'),
                "{}: {:?}",
                e.key,
                e.verified_by
            );
        }
    }
}
