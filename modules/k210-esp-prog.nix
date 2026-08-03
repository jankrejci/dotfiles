# Udev rules for the K210 bench esp-prog, an FTDI FT2232H at 0403:6010.
#
# Adopted from avalon-main-maixbit/assets/70-k210-esp-prog.rules. Numbered
# after the probe-rs rules in probe-rs.nix, which grant access to this same
# device but address neither problem below. Both are needed.
#
# One esp-prog drives a K210 board on two channels at once. Channel A,
# interface 00, is the JTAG side probe-rs opens through libusb. Channel B,
# interface 01, is the kflash ISP UART, and it also drives the board's reset
# and boot-mode nets.
#
# Install via services.udev.packages so the filename is preserved rather than
# merged into a single generated rules file.
{pkgs, ...}: {
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "k210-esp-prog-udev-rules";
      destination = "/etc/udev/rules.d/70-k210-esp-prog.rules";
      text = ''
        ACTION!="add|change|move|bind", GOTO="k210_esp_prog_end"

        # Release Channel A from ftdi_sio. probe-rs drives JTAG by claiming the
        # raw USB interface, which the serial driver would block. Channel B
        # stays bound as the ISP UART.
        #
        # On every bind rather than once per session. ftdi_sio claims both
        # interfaces on every bind event, including the ones a mid-session USB
        # re-enumeration produces, and losing the interface that way surfaces
        # as "Timeout during DMI access" partway through a connect that has
        # already read MISA and both harts' triggers. A dev shell hook that
        # releases Channel A at shell entry cannot cover a re-enumeration
        # during a cargo run.
        #
        # Change is matched too so the rule can be applied to a probe that is
        # already connected. Activating a configuration only restarts
        # systemd-udevd and replays no bind event, so such a probe keeps
        # Channel A on ftdi_sio until a replug or a udevadm trigger
        # --action=change. Widening the match costs nothing, because
        # DRIVER=="ftdi_sio" fails on an interface that is already unbound, so
        # a replayed change event on a released Channel A is a no-op.
        #
        # Deliberately not scoped to an EEPROM serial. A stock esp-prog ships
        # with a blank 93C46 and exposes no serial attribute at all, so an
        # ATTRS{serial} predicate matches nothing and silently disables the
        # rule. The cost is that interface 00 of every 0403:6010 loses its tty
        # on every host importing desktop.nix, not only the bench. Interface 01
        # is untouched, the bench probe is the only FT2232H in use here, and
        # probe-rs.nix and saleae.nix are scoped the same way.
        ACTION=="bind|change", SUBSYSTEM=="usb", DRIVER=="ftdi_sio", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", ATTR{bInterfaceNumber}=="00", RUN+="${pkgs.runtimeShell} -c 'echo -n %k > /sys/bus/usb/drivers/ftdi_sio/unbind'"

        # Keep ModemManager off both channels. NetworkManager pulls the daemon
        # in on every desktop host here. The esp-prog inverts Channel B's
        # DTR/RTS through Q1 and Q2 into the K210 reset and boot-mode nets,
        # which is what kflash's --invert compensates for, so a modem probe of
        # that port resets the board and can leave it in the boot ROM's ISP
        # mode instead of running the flashed image. The symptom is a board
        # that comes up after a power cycle and then resets in a loop after
        # every flash. udev tags the port ID_MM_CANDIDATE=1, so the daemon
        # probes it wherever it is installed.
        #
        # Tagged on each tty port, matching the port and walking up with ATTRS
        # to identify the device. ModemManager's own blacklists, for example the
        # u-blox GPS entries in 77-mm-ublox-port-types.rules, leave the
        # subsystem unrestricted and so tag the tty, the usb_interface and the
        # usb_device alike. Restricting to tty is enough because the daemon
        # reads the property through mm_kernel_device_get_global_property, which
        # falls back to the port itself when the port's physical device does not
        # carry it.
        ACTION=="add|change|move", SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", ENV{ID_MM_DEVICE_IGNORE}="1"

        LABEL="k210_esp_prog_end"
      '';
    })
  ];
}
