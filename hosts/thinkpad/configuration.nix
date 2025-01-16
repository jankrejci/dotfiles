{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/displaylink.nix
    ../../modules/disable-nvidia.nix
    ../../modules/audio.nix
    ../../modules/wg-client.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-c2bd7e97-dd43-4663-9c86-ab3a1ae3a822".device = "/dev/disk/by-uuid/c2bd7e97-dd43-4663-9c86-ab3a1ae3a822";

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking.hostName = "thinkpad";

  # Enable networking
  networking.networkmanager.enable = true;

  networking.wg-quick.interfaces.wg0 = {
    address = [ "192.168.99.4" ];
    privateKeyFile = "/home/jkr/.wg/jkr-thinkpad";
    dns = [ "192.168.99.1" "home" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = "192.168.99.4";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
