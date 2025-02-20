{ lib, pkgs, config, hostConfig, ... }:
let
  # Define paths to the decrypted secrets
  ssidPath = config.sops.secrets."wifi_ssid".path;
  pskPath = config.sops.secrets."wifi_psk".path;

  # Path where the wpa_supplicant configuration will be generated
  wpaConfigFolder = "/var/lib/wpa_supplicant";
  wpaConfigPath = "${wpaConfigFolder}/wpa_supplicant.conf";
in
{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";


  hardware = {
    enableRedistributableFirmware = lib.mkForce false;
    firmware = [ pkgs.raspberrypiWirelessFirmware ];
    deviceTree.filter = "bcm2837-rpi-zero*.dtb";
  };

  boot = {
    loader = {
      # Use the extlinux boot loader. NixOS wants to enable GRUB by default.
      grub.enable = false;
      # Enables the generation of /boot/extlinux/extlinux.conf
      generic-extlinux-compatible.enable = true;
    };
    initrd = {
      availableKernelModules = [ "xhci_pci" ];
      kernelModules = [ ];
    };
    kernelModules = [ ];
    extraModulePackages = [ ];
    extraModprobeConfig = ''
      options cfg80211 ieee80211_regdom=CZ
      options brcmfmac roamoff=1 feature_disable=0x82000
    '';
  };

  swapDevices = [ ];

  sdImage = {
    compressImage = false;
    imageName = "${hostConfig.hostName}-sdcard.img";
  };

  # TODO find out more unused services to disable
  # Disable unneeded features
  services = {
    avahi.enable = false;
    nfs.server.enable = false;
    samba.enable = false;
    journald.extraConfig = "Storage=volatile";
  };

  # TODO Turn off BT properly, it still emmits some errors
  # I dont need the bluetooth so far
  hardware.bluetooth.enable = false;

  # TODO find out how to share multiple wifi config in a better way
  sops = {
    secrets = {
      "wifi_ssid" = { mode = "0400"; owner = "systemd-network"; };
      "wifi_psk" = { mode = "0400"; owner = "systemd-network"; };
    };
  };

  # Ensure wpa_supplicant is installed
  environment = {
    systemPackages = with pkgs; [ wpa_supplicant ];
    etc."wpa_supplicant.conf".source = wpaConfigPath;
  };

  # Enable wpa_supplicant service
  networking = {
    wireless = {
      enable = true;
      userControlled.enable = false;
      interfaces = [ "wlan0" ];
    };
    supplicant.wlan0 = {
      driver = "nl80211";
      configFile.path = "/etc/wpa_supplicant.conf";
    };
    # Do not use network manager as it brings lot of dependencies
    networkmanager.enable = false;
    # Use systemd-networking dhcp
    useDHCP = lib.mkForce false;
    interfaces = {
      end0.useDHCP = true;
      wlan0.useDHCP = true;
    };
  };

  systemd.services = {
    # Ensure wpa_supplicant starts after the configuration is generated
    wpa_supplicant.after = [ "wpa-generate-config.service" ];
    # Systemd service to generate the wpa_supplicant configuration at runtime
    "wpa-generate-config" = {
      description = "Generate wpa_supplicant configuration from SOPS secrets";
      after = [ "network-pre.target" ];
      before = [ "wpa_supplicant.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        SSID=$(cat ${ssidPath})
        PSK=$(cat ${pskPath})
        mkdir -p ${wpaConfigFolder}
        cat > ${wpaConfigPath} <<EOF
        network={
          ssid="$SSID"
          psk="$PSK"
        }
        EOF
        chmod 600 ${wpaConfigPath}
        chown root:root ${wpaConfigPath}
      '';
    };
  };

  # Reboot after first boot to get config in place
  systemd.services."first-boot-reboot" = {
    description = "Reboot after first boot initialization";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionFirstBoot = true;
    script = ''
      echo "First boot detected. Rebooting system."
      systemctl reboot
    '';
  };
}

