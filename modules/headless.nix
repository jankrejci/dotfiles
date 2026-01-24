# Server-specific packages for headless x86_64 systems.
# Used by: thinkcenter, vpsfree
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # Network diagnostics
    nmap
    wireguard-tools

    # System management
    gitMinimal
    nix-tree
    sbctl
    lshw
  ];
}
