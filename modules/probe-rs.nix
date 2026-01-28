# Udev rules for embedded debugging hardware
#
# - plugdev group for device access
# - Espressif USB JTAG and serial debug units
# - required for probe-rs with ESP32
{
  # Create the plugdev group
  users.groups.plugdev = {};

  services.udev.extraRules = ''
    # This rules are based on the udev rules from the OpenOCD project, with unsupported probes removed.
    # See http://openocd.org/ for more details.
    #
    # This file is available under the GNU General Public License v2.0

    ACTION!="add|change", GOTO="probe_rs_rules_end"

    SUBSYSTEM=="gpio", MODE="0660", GROUP="plugdev", TAG+="uaccess"

    SUBSYSTEM!="usb|tty|hidraw", GOTO="probe_rs_rules_end"

    # Please keep this list sorted by VID:PID

    # Espressif USB JTAG/serial debug unit
    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", MODE="660", GROUP="plugdev", TAG+="uaccess"
    # Espressif USB Bridge
    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1002", MODE="660", GROUP="plugdev", TAG+="uaccess"

    LABEL="probe_rs_rules_end"
  '';
}
