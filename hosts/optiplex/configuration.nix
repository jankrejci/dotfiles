{ ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/displaylink.nix
    ../../modules/audio.nix
    ../../modules/wg-client.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-4146767d-b4f4-4a2e-be33-f12e11165724".device = "/dev/disk/by-uuid/4146767d-b4f4-4a2e-be33-f12e11165724";

  networking.hostName = "optiplex";

  # Enable networking
  networking.networkmanager.enable = true;

  networking.wireguard.interfaces.wg0 = {
    ips = [ "192.168.99.3/24" ];
    privateKeyFile = "/home/jkr/.wg/jkr-optiplex";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
