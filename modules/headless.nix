# Server packages for headless x86_64 systems
#
# - network diagnostics: nmap, wireguard-tools
# - system management: git, nix-tree, sbctl, lshw
# - used by: thinkcenter, vpsfree
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
