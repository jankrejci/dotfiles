# Udev rules for Saleae Logic analyzers
#
# The saleae-logic-2 package ships the software but not its udev rules, so
# the USB device stays root-only and the app cannot open it as a normal user.
#
# VID:PID list matches the vendor's 99-SaleaeLogic.rules bundled in the
# package, but access is scoped like probe-rs.nix: plugdev group plus the
# uaccess tag granting an ACL to the active seat, instead of the vendor's
# world-writable MODE="0666".
#
# The file must sort before systemd's 73-seat-late.rules, otherwise the
# uaccess tag is set too late and no ACL is applied. Install via
# services.udev.packages so the filename is preserved rather than merged
# into a single generated rules file.
{pkgs, ...}: {
  # probe-rs.nix declares the same group; declaring it here as well keeps
  # the module self-contained when imported without probe-rs.nix.
  users.groups.plugdev = {};

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "saleae-logic-udev-rules";
      destination = "/etc/udev/rules.d/70-saleae-logic.rules";
      text = ''
        # Saleae Logic USB analyzers, seat-scoped access via uaccess with
        # plugdev group fallback for non-seat sessions.
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0925", ATTR{idProduct}=="3881", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1001", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1003", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1004", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1005", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1006", MODE="0660", GROUP="plugdev", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="21a9", ATTR{idProduct}=="1007", MODE="0660", GROUP="plugdev", TAG+="uaccess"
      '';
    })
  ];
}
