//! Tests of the firmware line parsers.

use super::{Firmware, HostAction, NoMatch, Reading, Temps, M27};

#[test]
fn temps_with_ok_prefix() {
    let t = "ok T:21.7 /0.0 B:21.8 /0.0 T0:21.7 /0.0 @:0 B@:0 P:0.0 A:33.0"
        .parse::<Temps>()
        .unwrap();
    assert_eq!(
        t,
        Temps {
            tool: Reading {
                actual: 21.7,
                target: 0.0
            },
            bed: Reading {
                actual: 21.8,
                target: 0.0
            }
        }
    );
}

#[test]
fn temps_autoreport_with_targets() {
    let t = "T:215.3 /215.0 B:60.1 /60.0 T0:215.3 /215.0 @:30 B@:12"
        .parse::<Temps>()
        .unwrap();
    assert_eq!(t.tool.actual, 215.3);
    assert_eq!(t.tool.target, 215.0);
    assert_eq!(t.bed.target, 60.0);
}

#[test]
fn temps_rejects_other_lines() {
    assert!("ok".parse::<Temps>().is_err());
    assert!("Not SD printing".parse::<Temps>().is_err());
    assert!("T0:21.7 /0.0".parse::<Temps>().is_err());
}

#[test]
fn m27_variants() {
    assert_eq!("Not SD printing".parse::<M27>(), Ok(M27::NotPrinting));
    assert_eq!(
        "SD printing byte 1234/5678".parse::<M27>(),
        Ok(M27::Printing {
            done: 1234,
            total: 5678
        })
    );
    assert_eq!("SD print paused".parse::<M27>(), Ok(M27::Paused));
    assert_eq!("// action:paused".parse::<M27>(), Err(NoMatch));
    assert_eq!("echo:Print paused by the user".parse::<M27>(), Err(NoMatch));
    assert_eq!("ok".parse::<M27>(), Err(NoMatch));
}

#[test]
fn m115_firmware() {
    let line = "FIRMWARE_NAME:Prusa-Firmware 3.14.1+7500 based on Marlin FIRMWARE_URL:https://github.com/prusa3d/Prusa-Firmware PROTOCOL_VERSION:1.0 MACHINE_TYPE:Prusa i3 MK3S EXTRUDER_COUNT:1 UUID:00000000-0000-0000-0000-000000000000";
    assert_eq!(
        line.parse::<Firmware>().unwrap(),
        Firmware("Prusa-Firmware 3.14.1+7500 based on Marlin (Prusa i3 MK3S)".to_string())
    );
    assert!("ok".parse::<Firmware>().is_err());
}

#[test]
fn host_actions() {
    assert_eq!("//action:paused".parse(), Ok(HostAction::Paused));
    assert_eq!("//action:resumed".parse(), Ok(HostAction::Resumed));
    assert_eq!("//action:cancel".parse(), Ok(HostAction::Cancel));
    assert_eq!("// action:paused".parse(), Ok(HostAction::Paused));
    assert_eq!("// action:resumed".parse(), Ok(HostAction::Resumed));
    assert_eq!("// action:cancel".parse(), Ok(HostAction::Cancel));
    assert_eq!("//action:pause".parse::<HostAction>(), Err(NoMatch));
    assert_eq!("// action:pause".parse::<HostAction>(), Err(NoMatch));
    assert_eq!("ok".parse::<HostAction>(), Err(NoMatch));
}
