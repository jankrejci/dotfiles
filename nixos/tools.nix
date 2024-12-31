{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    neofetch
    vim
    wget
    curl
    git
    usbutils
    pciutils
    lshw
  ];
}
