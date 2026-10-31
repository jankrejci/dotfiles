use tokio::process::Command;

/// A camera that accepts the connection and then stalls would hang ffmpeg without end.
/// The value is in microseconds, the unit of the ffmpeg `rw_timeout` option, which covers
/// the http and tls layers of the video URL.
const INPUT_TIMEOUT_US: &str = "10000000";

/// The video stream and the ffmpeg binary that reads it.
#[derive(Clone)]
pub struct Input {
    pub ffmpeg: String,
    pub url: String,
}

impl Input {
    /// Returns a command with the input flags that snapshots and the live feed share, so the
    /// caller only appends its output options.
    pub fn command(&self) -> Command {
        let mut cmd = Command::new(&self.ffmpeg);
        cmd.args(["-nostdin", "-loglevel", "error"])
            .args(["-rw_timeout", INPUT_TIMEOUT_US])
            .args(["-i", &self.url]);
        cmd
    }
}
