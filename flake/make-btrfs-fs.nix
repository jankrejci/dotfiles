# Upstream make-btrfs-fs with a mkfs.btrfs that writes every file as root.
#
# Since btrfs-progs 6.10 mkfs.btrfs walks the source tree in a way fakeroot
# cannot intercept, so the image keeps the uid of the build sandbox. A root
# owned by uid 1000 breaks every tool that checks ownership, such as sshd
# refusing the AuthorizedKeysCommand and logrotate ignoring its config. The
# upstream fix runs mkfs under unshare instead, which fails for aarch64 images
# built under qemu, so the ownership is forced in mkfs itself.
# See: https://github.com/NixOS/nixpkgs/issues/401263
{
  pkgs,
  btrfs-progs,
  ...
} @ args:
pkgs.callPackage (pkgs.path + "/nixos/lib/make-btrfs-fs.nix") (
  removeAttrs args ["pkgs"]
  // {
    btrfs-progs = btrfs-progs.overrideAttrs (old: {
      # Upstream postPatch lacks a trailing newline, so start on a fresh line.
      postPatch =
        (old.postPatch or "")
        + "\n"
        + ''
          substituteInPlace mkfs/rootdir.c \
            --replace-fail 'btrfs_set_stack_inode_uid(dst, st->st_uid)' 'btrfs_set_stack_inode_uid(dst, 0)' \
            --replace-fail 'btrfs_set_stack_inode_gid(dst, st->st_gid)' 'btrfs_set_stack_inode_gid(dst, 0)'
        '';
    });
  }
)
