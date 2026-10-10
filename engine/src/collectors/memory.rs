use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

/// Memory headroom and pressure.
///
/// This panel exists because of a specific failure mode: a parallel build
/// quietly eats the machine and the OOM killer takes out something unrelated.
/// `available_kb` is the number that matters (not `free_kb` - most of "used"
/// is reclaimable cache), and PSI tells you whether reclaim is actually
/// hurting, which a headroom number alone cannot.
pub struct MemoryCollector;

#[derive(Debug, Serialize)]
struct MemoryReading {
    total_kb: u64,
    available_kb: u64,
    free_kb: u64,
    swap_total_kb: u64,
    swap_free_kb: u64,
    /// Fraction of MemTotal that is unavailable, 0.0-1.0.
    used_fraction: f64,
    /// %% of the last 10s / 60s where *some* task stalled on memory.
    /// Non-zero means reclaim is costing real time. Absent on kernels
    /// without CONFIG_PSI.
    pressure_some_avg10: Option<f64>,
    pressure_some_avg60: Option<f64>,
    pressure_full_avg10: Option<f64>,
}

fn parse_meminfo(text: &str) -> std::collections::HashMap<&str, u64> {
    text.lines()
        .filter_map(|line| {
            let (key, rest) = line.split_once(':')?;
            let kb = rest.split_whitespace().next()?.parse().ok()?;
            Some((key, kb))
        })
        .collect()
}

/// Parses one line of /proc/pressure/memory, e.g.
/// `some avg10=0.00 avg60=0.00 avg300=0.00 total=29007440`
fn parse_pressure_line(line: &str, field: &str) -> Option<f64> {
    line.split_whitespace()
        .find_map(|kv| kv.strip_prefix(field)?.strip_prefix('=')?.parse().ok())
}

impl Collector for MemoryCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "memory",
            title: "Memory",
            description: "Available memory and stall pressure",
            interval_secs: 2,
            subject: Subject::NixOS,
            info: Info {
                what: "Memory the kernel believes it could hand out without \
                       swapping, plus how much time tasks are losing to \
                       reclaim.",
                why: "Free memory alone is a poor signal: most of \"used\" is \
                      reclaimable page cache, so a healthy machine looks \
                      alarming. Headroom and stall pressure together tell you \
                      whether the machine is actually struggling.",
                if_wrong: "Available under ~1 GB with non-zero stall means \
                           reclaim is costing real time - the next big build \
                           may trigger the OOM killer, which tends to take an \
                           unrelated process with it.",
            },
            stats: vec![
                StatInfo {
                    key: "total_kb",
                    info: Info {
                        what: "MemTotal: physical RAM the kernel manages.",
                        why: "The ceiling everything else is measured against.",
                        if_wrong: "Only wrong if it changes, which would mean a \
                               hardware or VM reconfiguration.",
                    },
                },
                StatInfo {
                    key: "available_kb",
                    info: Info {
                        what: "MemAvailable: an estimate of what a new process \
                           could get without swapping, counting reclaimable \
                           cache as available.",
                        why: "This is the number that predicts whether the next \
                          allocation succeeds. free_kb does not.",
                        if_wrong: "Below ~500 MB, expect the OOM killer during a \
                               parallel build. Reduce job count before it \
                               picks a victim for you.",
                    },
                },
                StatInfo {
                    key: "free_kb",
                    info: Info {
                        what: "MemFree: pages holding nothing at all.",
                        why: "Shown for completeness; it is routinely low on a \
                          healthy machine because the kernel uses spare RAM \
                          for cache rather than wasting it.",
                        if_wrong: "A low value here alone is not a problem. Judge \
                               by available_kb instead.",
                    },
                },
                StatInfo {
                    key: "swap_total_kb",
                    info: Info {
                        what: "Configured swap.",
                        why: "Swap is the buffer between memory pressure and the \
                          OOM killer.",
                        if_wrong: "Zero swap means pressure turns into kills with \
                               no warning phase.",
                    },
                },
                StatInfo {
                    key: "swap_free_kb",
                    info: Info {
                        what: "Swap not currently in use.",
                        why: "Falling swap while available_kb is also low means \
                          the buffer is being spent.",
                        if_wrong: "Near zero with low available memory is the \
                               state immediately before an OOM kill.",
                    },
                },
                StatInfo {
                    key: "used_fraction",
                    info: Info {
                        what: "1 - available/total, as a fraction.",
                        why: "A single number for the headroom trend, and what \
                          the sparkline plots.",
                        if_wrong: "Above ~0.9 sustained during a build is the \
                               shape that precedes a kill.",
                    },
                },
                StatInfo {
                    key: "pressure_some_avg10",
                    info: Info {
                        what: "PSI: percentage of the last 10s in which at least \
                           one task stalled waiting for memory.",
                        why: "Distinguishes \"cache is full\" (harmless) from \
                          \"reclaim is costing time\" (not harmless).",
                        if_wrong: "Anything sustained above ~10 means real time \
                               is being lost to reclaim right now.",
                    },
                },
                StatInfo {
                    key: "pressure_some_avg60",
                    info: Info {
                        what: "The same measure averaged over 60 seconds.",
                        why: "Less twitchy than avg10; better for deciding \
                          whether a trend is real.",
                        if_wrong: "Above ~1 means the machine has been under \
                               genuine memory pressure for a while.",
                    },
                },
                StatInfo {
                    key: "pressure_full_avg10",
                    info: Info {
                        what: "PSI full: percentage of the last 10s in which \
                           *every* runnable task was stalled on memory.",
                        why: "Non-zero here means the machine was doing no useful \
                          work at all for that fraction of time.",
                        if_wrong: "Any sustained non-zero value is severe; the \
                               system is thrashing.",
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let meminfo = std::fs::read_to_string("/proc/meminfo").context("reading /proc/meminfo")?;
        let m = parse_meminfo(&meminfo);
        let get = |k: &str| -> Result<u64> {
            m.get(k)
                .copied()
                .with_context(|| format!("{k} missing from /proc/meminfo"))
        };

        let total_kb = get("MemTotal")?;
        let available_kb = get("MemAvailable")?;

        // PSI is optional: absent without CONFIG_PSI, and absent in some
        // containers. Missing pressure must not fail the panel.
        let pressure = std::fs::read_to_string("/proc/pressure/memory").ok();
        let line_of = |prefix: &str| -> Option<String> {
            pressure
                .as_ref()?
                .lines()
                .find(|l| l.starts_with(prefix))
                .map(str::to_owned)
        };
        let some = line_of("some");
        let full = line_of("full");

        let reading = MemoryReading {
            total_kb,
            available_kb,
            free_kb: get("MemFree")?,
            swap_total_kb: get("SwapTotal").unwrap_or(0),
            swap_free_kb: get("SwapFree").unwrap_or(0),
            used_fraction: if total_kb == 0 {
                0.0
            } else {
                1.0 - (available_kb as f64 / total_kb as f64)
            },
            pressure_some_avg10: some
                .as_deref()
                .and_then(|l| parse_pressure_line(l, "avg10")),
            pressure_some_avg60: some
                .as_deref()
                .and_then(|l| parse_pressure_line(l, "avg60")),
            pressure_full_avg10: full
                .as_deref()
                .and_then(|l| parse_pressure_line(l, "avg10")),
        };

        Ok(serde_json::to_value(reading)?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        let avail_gb = v["available_kb"].as_u64().unwrap_or(0) as f64 / 1_048_576.0;
        let stall = v["pressure_some_avg60"].as_f64().unwrap_or(0.0);

        // Headroom alone is a bad alarm: cache makes "used" look alarming on a
        // perfectly healthy machine. Bad means low headroom AND reclaim
        // actually costing time.
        let status = if avail_gb < 0.5 || stall > 10.0 {
            Status::Bad
        } else if avail_gb < 1.2 || stall > 1.0 {
            Status::Warn
        } else {
            Status::Ok
        };
        (status, format!("{avail_gb:.1} GB available"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_meminfo_lines() {
        let m = parse_meminfo("MemTotal:        7870192 kB\nMemFree:   358116 kB\n");
        assert_eq!(m.get("MemTotal"), Some(&7_870_192));
        assert_eq!(m.get("MemFree"), Some(&358_116));
    }

    #[test]
    fn parses_pressure_fields() {
        let line = "some avg10=1.25 avg60=0.50 avg300=0.00 total=29007440";
        assert_eq!(parse_pressure_line(line, "avg10"), Some(1.25));
        assert_eq!(parse_pressure_line(line, "avg60"), Some(0.50));
        assert_eq!(parse_pressure_line(line, "nope"), None);
    }

    #[test]
    fn samples_this_machine() {
        let v = MemoryCollector
            .sample()
            .expect("should read /proc on linux");
        assert!(v["total_kb"].as_u64().unwrap() > 0);
        assert!(v["used_fraction"].as_f64().unwrap() >= 0.0);
    }
}
