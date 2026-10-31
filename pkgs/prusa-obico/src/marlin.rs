//! Parsers for the lines that the Prusa firmware sends over the serial link. Nothing here
//! touches the shared state or the link, so both depend on it and neither on the other.

use serde::Serialize;
use std::str::FromStr;

/// The line is not the kind of reply the parser looks for.
#[derive(Debug, PartialEq, Eq)]
pub struct NoMatch;

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub struct Reading {
    pub actual: f64,
    pub target: f64,
}

/// Serializes in the OctoPrint shape that Obico and the status endpoint both use.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub struct Temps {
    #[serde(rename = "tool0")]
    pub tool: Reading,
    pub bed: Reading,
}

impl FromStr for Temps {
    type Err = NoMatch;

    fn from_str(line: &str) -> Result<Self, NoMatch> {
        let mut tool = None;
        let mut bed = None;
        let mut tokens = line.split_whitespace().peekable();
        while let Some(token) = tokens.next() {
            let (slot, rest) = match (token.strip_prefix("T:"), token.strip_prefix("B:")) {
                (Some(rest), _) => (&mut tool, rest),
                (None, Some(rest)) => (&mut bed, rest),
                (None, None) => continue,
            };
            // The target is usually a separate token, but "21.7/0.0" is tolerated too.
            let (actual, target) = match rest.split_once('/') {
                Some((a, t)) => (a, Some(t)),
                None => {
                    let target = tokens
                        .next_if(|t| t.starts_with('/'))
                        .and_then(|t| t.strip_prefix('/'));
                    (rest, target)
                }
            };
            let actual: f64 = actual.parse().map_err(|_| NoMatch)?;
            let target: f64 = target.and_then(|t| t.parse().ok()).unwrap_or(0.0);
            *slot = Some(Reading { actual, target });
        }
        Ok(Temps {
            tool: tool.ok_or(NoMatch)?,
            bed: bed.ok_or(NoMatch)?,
        })
    }
}

#[derive(Debug, PartialEq)]
pub enum M27 {
    Printing { done: u64, total: u64 },
    NotPrinting,
    Paused,
}

impl FromStr for M27 {
    type Err = NoMatch;

    fn from_str(line: &str) -> Result<Self, NoMatch> {
        // Only the M27 reply itself counts. An echo or action line that mentions a pause must not.
        if line.starts_with("SD print") && line.to_ascii_lowercase().contains("paused") {
            return Ok(M27::Paused);
        }
        if line.contains("Not SD printing") {
            return Ok(M27::NotPrinting);
        }
        let rest = line.split("SD printing byte").nth(1).ok_or(NoMatch)?;
        let (done, total) = rest.trim().split_once('/').ok_or(NoMatch)?;
        Ok(M27::Printing {
            done: done.trim().parse().map_err(|_| NoMatch)?,
            total: total
                .split_whitespace()
                .next()
                .and_then(|t| t.parse().ok())
                .ok_or(NoMatch)?,
        })
    }
}

/// The human readable firmware description from an M115 reply.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(transparent)]
pub struct Firmware(String);

impl FromStr for Firmware {
    type Err = NoMatch;

    fn from_str(line: &str) -> Result<Self, NoMatch> {
        if !line.starts_with("FIRMWARE_NAME:") {
            return Err(NoMatch);
        }
        let mut fields: Vec<(String, String)> = Vec::new();
        for word in line.split(' ') {
            let key = word.split_once(':').filter(|(k, _)| {
                !k.is_empty() && k.chars().all(|c| c.is_ascii_uppercase() || c == '_')
            });
            match (key, fields.last_mut()) {
                (Some((k, v)), _) => fields.push((k.to_string(), v.to_string())),
                (None, Some((_, v))) => {
                    v.push(' ');
                    v.push_str(word);
                }
                (None, None) => {}
            }
        }
        let get = |name: &str| {
            fields
                .iter()
                .find(|(k, _)| k == name)
                .map(|(_, v)| v.clone())
        };
        let firmware = get("FIRMWARE_NAME").ok_or(NoMatch)?;
        Ok(Self(match get("MACHINE_TYPE") {
            Some(machine) => format!("{firmware} ({machine})"),
            None => firmware,
        }))
    }
}

/// A host action line of the Prusa firmware. The firmware emits them for every pause, resume and
/// stop, whether it came from the printer menu or from M601, M602 and M603, so they are the only
/// way to notice a pause or stop that did not come from Obico. A filament change with M600 emits
/// the paused and resumed lines as well.
#[derive(Debug, PartialEq, Eq)]
pub enum HostAction {
    Paused,
    Resumed,
    Cancel,
}

impl FromStr for HostAction {
    type Err = NoMatch;

    fn from_str(line: &str) -> Result<Self, NoMatch> {
        // Firmware 3.13.3 and older releases put a space after the slashes and 3.14.1 does not.
        let action = line.strip_prefix("//").ok_or(NoMatch)?.trim_start();
        match action {
            "action:paused" => Ok(Self::Paused),
            "action:resumed" => Ok(Self::Resumed),
            "action:cancel" => Ok(Self::Cancel),
            _ => Err(NoMatch),
        }
    }
}

#[cfg(test)]
#[path = "tests/marlin.rs"]
mod tests;
