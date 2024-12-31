{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    linuxKernel.packages.linux_6_6.evdi
    displaylink
  ];
  services.xserver.videoDrivers = [ "displayLink" "modesetting" ];
}
