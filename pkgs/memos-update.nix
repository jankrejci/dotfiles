# Memos 0.26.1 overlay
#
# Required for moe-memos Android client compatibility.
# Remove once nixpkgs-unstable includes memos 0.26.1.
final: prev: {
  unstable =
    prev.unstable
    // {
      memos = final.callPackage ./memos/package.nix {};
    };
}
