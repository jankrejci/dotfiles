//! Tests of the command line value parsers.

use super::first_dir;
use std::path::PathBuf;

#[test]
fn first_state_directory_wins() {
    assert_eq!(
        first_dir("/var/lib/a:/var/lib/b"),
        Ok(PathBuf::from("/var/lib/a"))
    );
    assert!(first_dir("").is_err());
    assert!(first_dir(":/var/lib/b").is_err());
}
