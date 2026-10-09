# Panels

A panel is one `Collector`: it samples something on an interval, keeps a
bounded history in memory, and judges its own latest value.

The judgement lives in the **engine**, not the UI. A colour is a claim about
severity, and a UI that invents one is duplicating reasoning it has no
business doing — which is how two front-ends end up disagreeing about the same
number.

```
GET /api/panels              every panel: metadata + latest sample
GET /api/panels/{id}?limit=N history, newest last (default 120, max 1000)
```

## The ones that exist

| id | interval | subject |
|---|---|---|
| `memory` | 2s | NixOS |
| `failed-units` | 15s | NixOS |
| `disk` | 30s | NixOS |
| `generations` | 60s | NixOS |
| `qt` | 60s | Qt |
| `rust` | 60s | Rust |

---

## `memory`

Reads `/proc/meminfo` and `/proc/pressure/memory`.

**Reports `available_kb`, not `free_kb`.** Most of what Linux calls "used" is
reclaimable page cache, so free memory looks alarming on a perfectly healthy
machine and means very little. `MemAvailable` is the kernel's own estimate of
what a new allocation could actually get. `free_kb` is still emitted, because
seeing the gap between the two is the point.

**PSI is the complement.** Headroom tells you how much is left; it cannot tell
you whether reclaim is *costing* anything. `/proc/pressure/memory` does:
`some avg60` is the fraction of the last minute in which at least one task was
stalled waiting on memory. A box can sit at 300 MB available with zero
pressure and be fine.

So the status is deliberately not a headroom threshold alone:

| | |
|---|---|
| **bad** | available < 0.5 GB **or** `some avg60` > 10% |
| **warn** | available < 1.2 GB **or** `some avg60` > 1% |

**If it looks wrong:** a high `used_fraction` with `some avg60` near zero is
cache doing its job — not a problem. Pressure climbing while headroom looks
fine is the interesting case, and usually means a working set that no longer
fits.

## `failed-units`

Runs `systemctl --failed` in **both** scopes — user and system.

**Zero failures and "I could not look" are different answers**, and conflating
them is how a monitoring tool reassures you about something it never checked.
So the panel emits `unavailable_scopes` alongside `count`, and a scope it
could not query makes the status `unknown` rather than `ok`.

The user scope needs the session D-Bus socket, which is why the service orders
itself `After=graphical-session-pre.target`. Without that the first few
samples legitimately report the user scope unavailable.

| | |
|---|---|
| **bad** | any unit failed |
| **unknown** | a scope could not be queried |

**If it looks wrong:** `restart-*` actions appear here, one per failed unit.
A unit that fails again immediately was failing *at start*, not crashing —
restarting it repeatedly will not help, and its journal will say why.

## `disk`

`statvfs` on the filesystem holding `/nix/store`.

**Uses `used / (used + avail)`, not `used / total`.** A filesystem reserves
blocks for root; counting them as space you have understates fullness by
several percent. On this machine the naive formula read 92.9% where `df` said
98% — the difference between "worth noting" and "the next rebuild fails".

| | |
|---|---|
| **bad** | > 93% used |
| **warn** | > 85% used |

Warning early is deliberate: a store fills slowly and then bites during a
rebuild, which is exactly when there is no good moment to deal with it.

**If it looks wrong:** old generations are almost always the cause. See
`gc-store` in [actions.md](actions.md).

## `generations`

Lists `/nix/var/nix/profiles/system-*-link` and compares `/run/booted-system`
with `/run/current-system`.

**Uses `symlink_metadata`, never `metadata`.** This cost real debugging time:
`metadata()` follows the symlink into the store, where Nix normalises every
mtime to epoch 1970. Any timestamp comparison against that is permanently
wrong — a drift check built on it fires forever and looks plausible while
doing so. The activation time lives on the **symlink itself**. A test asserts
the mtime is not epoch-ish, so the mistake cannot come back quietly.

| | |
|---|---|
| **warn** | a reboot is pending |

**If it looks wrong:** "reboot pending" is not urgent in itself — userspace is
already running the new generation. It matters when the difference is a kernel
or driver update, which is also exactly when something inexplicable tends to
be broken.

## `qt`

Answers **"will a Qt build work in this environment?"** — not "is Qt
installed".

It finds the `qmake` a build would actually pick up (`QMAKE` if set, else
`PATH`), records where that came from, and asks it for its prefix. Then it
checks that prefix for every host tool `cxx-qt` needs: `moc`, `rcc`,
`qmltyperegistrar`, `qmlcachegen`.

**Why that last check is the whole point.** On NixOS `qmltyperegistrar` and
`qmlcachegen` live in **qtdeclarative**, not qtbase. A prefix built from
qtbase alone looks entirely healthy — right version, right spec — and then
fails late in a build with a message about the tool, not about the prefix. And
`symlinkJoin` does not fix it: nixpkgs' qmake has its prefix baked in, so the
merged tree is ignored. `pkgs.qt6.env` is the thing that works, which is what
the `qt-merged-prefix` action hands you.

| | |
|---|---|
| **bad** | host tools missing from the prefix |

**If it looks wrong:** this describes the **engine's** environment — the
systemd user service's — not whichever shell you are sitting in. A devShell
with a complete prefix will not change what this panel says.

## `rust`

Same question, same shape: **will a cross build work here?**

Reports `rustc`/`cargo` versions and path, the host triple, the installed
**target** std libraries, and whether `lld` is on the PATH.

**Target std libraries, not installed toolchains.** nixpkgs' `rustc` ships the
host target only. Adding a `--target` it has no std for fails with *"can't
find crate for `std`"*, which reads like a missing crate rather than a missing
toolchain component. `has_wasm32_emscripten` and `has_wasm32_unknown` are
broken out because those are the two that matter for the Qt/wasm work.

| | |
|---|---|
| **warn** | `wasm32-unknown-unknown` present but no `lld` |
| **warn** | neither wasm target present |

A toolchain lacking a target is not *broken* — it is simply not the toolchain
for that target, hence warn rather than bad. `wasm32-unknown-unknown` without
`lld` genuinely is broken: it will fail at link, naming the linker.

**If it looks wrong:** same caveat as `qt` — this is the service's
environment. A test asserts fewer than 50 targets are parsed, which catches
reading the wrong `rustc` output format.

---

## Adding one

Implement `Collector` and register it. Nothing else changes — no shared enum,
no UI switch, no central list of ids.

```rust
pub trait Collector: Send + Sync + 'static {
    fn meta(&self) -> PanelMeta;
    fn sample(&self) -> anyhow::Result<serde_json::Value>;
    fn status(&self, value: &serde_json::Value) -> (Status, String);
}
```

The UI renders an unknown panel id with `GenericPanel`, which walks whatever
keys the sample contains. A new panel is therefore visible and explained
before anyone writes a custom component for it.

### Every field must be explained

`PanelMeta` carries an `Info { what, why, if_wrong }` for the panel and a
`StatInfo` for **every key the sample emits**. This is enforced:
`every_panel_and_stat_is_explained` fails if a key appears in the JSON with no
`StatInfo`, or if any `what`/`why`/`if_wrong` is empty.

The bar is the mechanism, not the label. *"Shows memory usage"* is a wasted
panel; *"most of 'used' is reclaimable cache, so this number looks alarming
and means little"* is the one worth having. Four good explanations beat twelve
filler ones.

### Cost

`sample()` runs on the interval, for the lifetime of the service. Keep it to
reads of `/proc`, a `statvfs`, or one short subprocess. Anything that walks
the store belongs in an action's copy-able text, where it runs when you ask
for it — not on a timer.
