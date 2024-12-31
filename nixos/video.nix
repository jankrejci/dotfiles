{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    displaylink
  ];

  services.xserver.videoDrivers = [ "displayLink" "modesetting" ];
}
