import QtQuick

// Every colour in the app, defined once.
//
// Before this there were 62 hex literals across 13 files and 20 distinct
// shades — three different greens for "good", three reds for "bad", two
// ambers for "pending" — each picked independently while writing the file it
// appeared in. The problem was never which hues; it was that one *role* had
// several values and nothing said which was correct.
//
// **Not a singleton**, which is the one thing that would be natural here.
// cxx-qt 0.10's QmlModule has no way to register one - no qmldir singleton
// marker, no per-file property - so `pragma Singleton` loads as an error.
// Instead this is an ordinary QtObject that each component instantiates:
//
//     Item {
//         Style { id: style }
//         Rectangle { color: style.surface }
//     }
//
// It holds nothing but constants, so an instance per component costs
// essentially nothing.
//
// ---------------------------------------------------------------------------
// The scheme is dark, deliberately and not by inheriting one. Text follows
// the rule from the RERAG repo: #d1d5db for anything you need to read,
// #9ca3af as the floor for secondary text, and never darker. Links are blue.
QtObject {
    // ---- surfaces ------------------------------------------------------
    readonly property color window:     "#1b1f24"   // page background
    readonly property color surface:    "#22272e"   // panels and tiles
    readonly property color surfaceAlt: "#2b313a"   // code blocks, insets
    readonly property color border:     "#3a424d"
    readonly property color borderSoft: "#2f3741"

    // ---- text ----------------------------------------------------------
    // Anything the reader needs: #d1d5db. Secondary: #9ca3af, and no darker -
    // the contrast failure is invisible until someone actually reads it on a
    // dark display.
    readonly property color text:       "#d1d5db"
    readonly property color textMuted:  "#9ca3af"
    readonly property color textStrong: "#f3f4f6"

    readonly property color link:       "#60a5fa"
    readonly property color linkHover:  "#93c5fd"

    // ---- status --------------------------------------------------------
    // One scale, four states, each with a dot colour, a readable text colour
    // and a tint for filled panels. Chosen for a dark background: the old
    // values were Material's light-theme shades and turn to mud here.
    readonly property color okDot:      "#4ade80"
    readonly property color okText:     "#86efac"
    readonly property color okTint:     "#16301f"

    readonly property color warnDot:    "#fbbf24"
    readonly property color warnText:   "#fcd34d"
    readonly property color warnTint:   "#33280f"

    readonly property color badDot:     "#f87171"
    readonly property color badText:    "#fca5a5"
    readonly property color badTint:    "#3a1d1e"

    readonly property color unknownDot:  "#9ca3af"
    readonly property color unknownText: "#9ca3af"
    readonly property color unknownTint: "#272c33"

    // Written-but-not-yet-applied, used by all three writable sections. The
    // same family as warn, because it is the same idea: not wrong, not
    // finished.
    readonly property color pendingText: warnText
    readonly property color pendingTint: warnTint

    // ---- badges --------------------------------------------------------
    // "paste into your Nix config" vs "run in a terminal" vs "needs root".
    readonly property color nixBadgeTint:     "#16293d"
    readonly property color nixBadgeText:     "#93c5fd"
    readonly property color shellBadgeTint:   "#2b313a"
    readonly property color shellBadgeText:   "#c5ccd6"
    readonly property color rootBadgeTint:    "#3a2a14"
    readonly property color rootBadgeText:    "#fcd34d"

    // ---- info button ---------------------------------------------------
    // The canonical spec from the RERAG repo, kept identical so the two
    // dashboards read as the same family: a 24px rounded square in the Rust
    // brand colour with a white glyph, not a tinted circle.
    readonly property color infoBg:     "#7C2A02"
    readonly property color infoBorder: "#7C2A02"
    readonly property color infoGlyph:  "#ffffff"
    readonly property int   infoSize:   24

    // ---- spacing -------------------------------------------------------
    readonly property int gapTight:  4
    readonly property int gap:       8
    readonly property int gapWide:   12
    readonly property int pad:       12
    readonly property int radius:    6

    // ---- helpers -------------------------------------------------------
    // Status strings come from the engine as "ok" | "warn" | "bad" |
    // "unknown". Mapping them here means a panel never has to carry its own
    // colour table, which is how the three greens happened.
    function dotFor(status) {
        if (status === "ok")   return okDot
        if (status === "warn") return warnDot
        if (status === "bad")  return badDot
        return unknownDot
    }
    function textFor(status) {
        if (status === "ok")   return okText
        if (status === "warn") return warnText
        if (status === "bad")  return badText
        return unknownText
    }
    function tintFor(status) {
        if (status === "ok")   return okTint
        if (status === "warn") return warnTint
        if (status === "bad")  return badTint
        return unknownTint
    }
}
