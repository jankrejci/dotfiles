{ config, ... }:
{
  # TODO Find out a way how to do this hack properly
  # 
  # To boot the raspberry device succesfully with an uart device connected,
  # you need to ignore the uart input. The thing is that U-Boot needs the
  # UART enabled, otherwise it fails booting.
  # To disable U-Boot keyboard input, disconnect UART device, interrupt boot
  # and jupm to the U-Boot> prompt, disable bootdelay entering this
  # `setenv bootdelay -2`
  # `savenv`
  # Next you need to disable extlinux prompt commenting out the MENU and TIMEOUT
  # entries in /boot/extlinux/extlinux.conf

  # TODO add obico plugin and enable the port
  services.octoprint = {
    enable = true;
    host = config.hosts.self.ipAddress;
  };

  nix.settings.trusted-public-keys = [
    "jkr@optiplex:KwH9qv7qCHd+npxC0FUFCApM1rP6GSbB8Ze983CCT8o="
  ];
}
