# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Does

**nixdash** is a local-first config-and-monitoring dashboard for one NixOS
machine: a Rust engine (axum, loopback only) collects system state, and a
Qt/QML UI renders it — compiled twice from one source, once natively and once
to WebAssembly.

**nixdash is also a learning platform.** It monitors three subjects — **NixOS,
Qt and Rust** — and is meant to teach how this machine actually works: why a
store path is read-only, why `PATH` has nothing to do with whether Qt runs,
what polkit is doing when it asks for a password. UI decisions (info panels,
visible stats, declared-vs-effective) exist to serve that: **make the
invisible visible**.

> The three subjects are things being *monitored*, not merely the stack it is
> written in. This was misread once and cost a rewrite.

## Build, Test, and Development Commands

```bash
# Engine dev server
cd engine && RUST_LOG=info cargo run

# Quality gate (must pass before committing)
cargo fmt --all && cargo clippy --all-targets -- -D warnings

# Tests
cargo test --all

# Desktop UI
nix develop --command bash -c 'cd ui && cargo build'

# Browser UI (separate toolchain: emcc + wasm32 Rust target)
nix develop .#wasm --command bash ui-wasm/build.sh
./ui-wasm/serve.sh                      # :8099

# Deploy
home-manager switch                     # then the restart it prints
systemctl --user restart nixdash-engine.service
```

## Collaboration Style

- **No speculative pre-builds.** Do not run `cargo build` or `cargo clippy`
  just to check for errors after an edit. Build errors surface when the user
  restarts the service. A build check wastes the user's time — and on this
  project a UI build is ~90 seconds and a `home-manager switch` is ~15
  minutes. The quality gate before a *commit* is the exception.
- **Do not launch the UI.** Not with `cargo run`, not on an Xvfb virtual
  display, not via `systemd-run`. The user runs it and reports what they see.
  Driving it with `xdotool` to take screenshots is the same violation wearing
  different clothes, and stealing window focus while the user is working is
  worse.
- **Confirmation threshold**: don't ask before small or single-file edits.
  Only ask before major or multi-file changes. Ending every message with
  "shall I continue?" is noise.
- **Commit directly to main.** Solo project, self-reviewed. No feature
  branches or PRs by default. Commit phase work straight to main; tag a
  release when a phase ships.
- **Report exit codes from the command itself**, never from a trailing `grep`
  in the same pipeline. `home-manager switch | grep …` reports grep's status,
  which has already been mistaken for a successful deploy once.

## Architecture

```
[desktop UI (cxx-qt)]   [browser UI (wasm)]
            │                   │
            └────── HTTP ───────┘   loopback only, :3100
                    │
            [engine (axum)]
                    │
  /proc · systemctl · /nix/var/nix/profiles · statvfs · qmake · rustc
```

One `qml/` directory, symlinked into `ui/qml` and `ui-wasm/rust/qml`. The
symlink is load-bearing: a `../qml/...` path corrupts the generated Qt
resource aliases. A new QML file must also be listed in **both**
`ui/build.rs` and `ui-wasm/rust/build.rs` or it will not be in the resource
bundle.

## Key Files

| File | Purpose |
|------|---------|
| `engine/src/collector.rs` | `Collector` trait, `Info`/`StatInfo`, `Panel` + ring buffer |
| `engine/src/collectors/` | one module per panel |
| `engine/src/actions/` | one module per action provider |
| `engine/src/actions/runner.rs` | execution: argv, pkexec, pipe draining, timeout |
| `engine/src/settings.rs` | the one place the engine writes a file |
| `engine/src/api.rs` | route registry |
| `qml/InfoButton.qml` | the explanation mechanism: tabs, rich text, links |
| `nix/hm-module.nix` | home-manager module — read the sandbox comment before editing |

## Coding Conventions

- **Indentation**: 4 spaces everywhere; tabs only in Makefiles
- **Rust naming**: `snake_case` modules/functions, `SCREAMING_SNAKE_CASE`
  constants, `UpperCamelCase` types
- **QML components**: `UpperCamelCase.qml` in `qml/`
- **Linting**: `cargo fmt --all` + `cargo clippy --all-targets -- -D warnings`
  must pass before a commit
- **Commits**: conventional form — `type(scope): lowercase description`, e.g.
  `fix(engine): read symlink mtime, not its target`

## Info Buttons

**Every control and every stat gets one.** Adding a control, a stat or an
automation step means adding its info panel *in the same change*, not as a
follow-up. Default to adding one; err towards too many.

This is enforced: `engine/tests/qml_info.rs` scans `qml/` for `Button`,
`TabButton` and `MouseArea` declarations and fails if one has no `InfoButton`
within 60 lines. Exemptions need a written reason, and a second test fails if
the reason is under 60 characters.

**Three questions, always**: what it is · why it matters · what a wrong value
looks like. Bodies are rich text — `<b>`, `<tt>` for commands and paths,
`<ul>`, `<table>`, and `<a href>` links that open in a browser. Long panels
split into tabs via `sections: [{ title, body }]`.

**Explain the mechanism, not the label.** "Shows memory usage" is a wasted
panel. "Most of 'used' is reclaimable cache, so this number looks alarming and
means little" is the one worth having.

## Info Panel Voice

Info panels are written from the perspective of someone using the app. To
them there is only **the app** — they do not know or care that it has an
engine and a UI talking over HTTP.

- ✅ user-visible technical terms: store paths, `PATH`, polkit, generations,
  ports, `home-manager switch`
- ❌ source-code architecture terms: "the engine", "the backend", "a
  collector", `spawn_blocking`, "DT_NEEDED", "the axum handler"

Where the distinction genuinely matters to the reader — the app's background
service has a different environment from their shell, which is why `qmake`
is not on its `PATH` — say *that*, in those words, rather than naming the
internal component.

## Honesty Rules

These are product requirements, not style preferences. Each one exists
because violating it shipped a bug.

- **A headline claims only what was measured.** "no qmake on PATH" — never
  "no Qt in this environment", from an app drawing its own window with
  libQt6Qml. Enforced by `headlines_claim_only_what_was_measured`.
- **"Nothing found" and "could not look" are different answers.** Report
  `unknown`, never `ok`, when a probe failed. A monitor that reassures you
  about something it never checked is worse than no monitor.
- **Never raise a false alarm.** A check probing for a binary named `clippy`
  reported a working toolchain as broken — there is no such binary, the
  package installs `cargo-clippy`.
- **Declared ≠ in effect.** On a declarative system these are two facts.
  Show both and let them disagree; never pretend a setting applied when it
  only wrote Nix source.
- **Displayed command ≠ executed command.** `command` is prose for a human
  and may lead with a dry-run. `run` is an explicit program + argv. Never
  derive one from the other.

## Privileges

The app holds no privilege of its own. Anything needing root goes through
`pkexec` → polkit → a prompt the user answers. **The prompt is the
authorisation.**

Two NixOS traps, both already paid for:

- `/run/current-system/sw/bin/pkexec` is **not setuid**; only
  `/run/wrappers/bin/pkexec` is. Search `/run/wrappers/bin` first.
- Seccomp-based systemd options (`SystemCallFilter`,
  `SystemCallArchitectures`, `LockPersonality`, `MemoryDenyWriteExecute`,
  `RestrictRealtime`, `RestrictSUIDSGID`) **imply `NoNewPrivileges`** in an
  unprivileged user unit, which makes setuid a no-op. `systemctl --user show`
  reports `NoNewPrivileges=no` while the kernel says `1`. Trust
  `/proc/<pid>/status`, not systemctl.

## Deploying

`nix/engine.nix` takes the **whole tree** as `src`, so *any* file change
rebuilds the engine to a new store path.

| Changed | To take effect |
|---|---|
| anything in the repo | `home-manager switch` + the printed `systemctl --user restart nixdash-engine.service` |
| `qml/`, `ui/` as well | close and reopen the window |
| panel icon / menu entry | `xfce4-panel -r` |

For UI work there is a cheaper loop than a switch, and the panel icon follows
it:

```bash
nix develop --command bash -c 'cargo build -p nixdash-ui && ./target/debug/nixdash-ui'
```

The menu entry and the panel launcher run a wrapper that starts **whichever
build is newer** — the local `target/debug/nixdash-ui` when its mtime beats the
generation symlink, the installed binary otherwise (`services.nixdash.ui.devBuild`,
null to always use the installed one). Store paths all share one epoch mtime,
which is why the comparison is against the generation link rather than the
store path. Without this the icon kept launching the last switched-in build
while a fresh one sat in the tree, and the two windows are indistinguishable.

`home.nix` sets `systemd.user.startServices = "suggest"`, so home-manager
prints the restart rather than running it — restarting user services
automatically takes xfconf down and kills the Xfce panel on this machine.
A changed service keeps running the **old** build until restarted, which the
`rust-build` panel reports.

## Security Notes

- The API is **unauthenticated** and bound to `127.0.0.1` unconditionally —
  not a setting. It must never be reachable from elsewhere.
- CORS is restricted to loopback origins. It was `permissive`, which was fine
  while every route was a read and is not fine now that a POST can raise a
  polkit prompt.
- `POST /api/actions/{id}/run` takes **no body**: the caller names an action,
  never a command, so the executable set is fixed at compile time.
- `POST /api/settings` does take a body, but only a key from a fixed list and
  a range- or enum-checked value. It writes exactly one generated file and
  rewrites it whole — it never parses or patches hand-written Nix.
