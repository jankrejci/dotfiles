//! Software UART TX for Raspberry Pi GPIO
//!
//! Bit-bangs UART output when hardware TX pin is dead.
//! Uses Linux GPIO character device via libgpiod.

use clap::Parser;
use gpiod::{Chip, Lines, Options, Output};
use log::info;
use std::io::{self, Read};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(name = "soft-uart-tx")]
#[command(about = "Software UART TX via GPIO bit-banging")]
struct Args {
    /// GPIO chip
    #[arg(short, long, default_value = "gpiochip0")]
    chip: String,

    /// GPIO line number
    #[arg(short = 'l', long, default_value = "4")]
    line: u32,

    /// Baud rate
    #[arg(short, long, default_value = "9600")]
    baud: u32,

    /// Read binary data from stdin
    #[arg(short, long)]
    stdin: bool,

    /// Hex data to send
    data: Option<String>,
}

struct SoftUart {
    line: Lines<Output>,
    bit_delay_ns: u64,
}

impl SoftUart {
    fn new(chip: &str, line_num: u32, baud: u32) -> io::Result<Self> {
        let chip = Chip::new(chip).map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;
        let opts = Options::output([line_num]).values([true]);
        let line = chip
            .request_lines(opts)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;

        Ok(Self {
            line,
            bit_delay_ns: 1_000_000_000 / baud as u64,
        })
    }

    /// Busy-wait for precise bit timing.
    /// At 9600 baud each bit is ~104us. thread::sleep has millisecond granularity on Linux
    /// so we spin instead. Burns 100% CPU while transmitting but acceptable for short
    /// UBX commands that complete in milliseconds.
    #[inline(always)]
    fn delay_ns(&self, ns: u64) {
        let start = Instant::now();
        while start.elapsed().as_nanos() < ns as u128 {}
    }

    #[inline(always)]
    fn write(&self, value: bool) {
        let _ = self.line.set_values([value]);
    }

    fn tx_byte(&self, byte: u8) {
        // Start bit
        self.write(false);
        self.delay_ns(self.bit_delay_ns);

        // Data bits, LSB first
        for i in 0..8 {
            self.write((byte >> i) & 1 != 0);
            self.delay_ns(self.bit_delay_ns);
        }

        // Stop bit
        self.write(true);
        self.delay_ns(self.bit_delay_ns);
    }

    fn tx_bytes(&self, data: &[u8]) {
        for &byte in data {
            self.tx_byte(byte);
        }
    }
}

fn get_data(args: &Args) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    if args.stdin {
        let mut buf = Vec::new();
        io::stdin().read_to_end(&mut buf)?;
        return Ok(buf);
    }

    let hex_data = args.data.as_ref().ok_or("No data specified. Use --help for usage.")?;
    Ok(hex::decode(hex_data)?)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    let args = Args::parse();

    let data = get_data(&args)?;
    let hex_str = data.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(" ");

    info!("TX {} line {} @ {} baud: {}", args.chip, args.line, args.baud, hex_str);

    let uart = SoftUart::new(&args.chip, args.line, args.baud)?;
    uart.tx_bytes(&data);

    // Keep line HIGH and hold before exit.
    // libgpiod releases line on drop, so we hold briefly to ensure GNSS sees stable HIGH.
    uart.write(true);
    thread::sleep(Duration::from_millis(100));

    Ok(())
}
