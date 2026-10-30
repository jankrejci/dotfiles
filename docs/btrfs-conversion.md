# Converting a host's root from ext4 to btrfs in place

Hosts using `modules/disk-tpm-encryption.nix` or
`modules/disk-password-encryption.nix` keep LUKS, LVM, swap and the ESP as
they are. Only the `pool/root` logical volume changes from ext4 to the btrfs
subvolume layout in `modules/disk-root-filesystem.nix`. The procedure below
was first run on framework on 2026-10-29.

## Status

| Host | State |
|------|-------|
| framework, t14 | converted and cleaned up |
| m75q | installed fresh as btrfs, no conversion needed |
| thinkcenter, e470, optiplex | ext4 |
| prusa | converted and deployed |
| rpi4, rak2245 | set to btrfs, not yet deployed |

## Before you start

- A recent installer from `nix run .#build-installer`. It joins the stored
  wifi networks and Netbird on its own and answers `ssh iso` with the host key
  pinned in `hosts.iso.hostPubkey`.
- The LUKS passphrase. The password slot is kept for recovery, so the
  installer can unlock the disk with it.
- Secure Boot off in the firmware. The installer is not signed with the
  enrolled keys.
- Home directories backed up elsewhere. The conversion keeps the old ext4 as
  an image, but that is not a backup.

## Steps

### 1. Unlock and check, on the console

```sh
sudo cryptsetup open /dev/nvme0n1p2 crypted
sudo vgchange -ay pool
sudo e2fsck -fn /dev/pool/root   # must report no problems
```

`btrfs-convert` refuses a filesystem that needs recovery. The `orphan_file`
ext4 feature is fine, btrfs-progs 6.19 skips that inode.

### 2. Back up the system state to t14

Everything that is not in the config and not under `/home`. Run from t14:

```sh
ssh iso 'mkdir -p /mnt/old && mount -o ro /dev/pool/root /mnt/old'
(umask 077; ssh iso 'cd /mnt/old && tar --numeric-owner --xattrs --acls -cpf - \
  etc/ssh var/lib/sbctl etc/NetworkManager/system-connections var/lib/bluetooth \
  var/lib/fprint var/lib/nixos etc/machine-id' > ~/HOST-state-DATE.tar)
ssh iso 'umount /mnt/old'
```

The archive holds the SSH host key and the Secure Boot signing keys. Add any
host-specific state, for example ESET under `/opt/eset`, `/etc/opt/eset`,
`/var/lib/eset` and `/var/opt/eset` on framework.

### 3. Convert

```sh
ssh iso 'systemd-run --unit=btrfs-convert --property=Type=exec \
  btrfs-convert --no-progress /dev/pool/root'
```

It runs as its own unit so a dropped connection does not stop it. It reads all
data once to compute checksums, about 36 minutes for 600 GiB on framework, and
logs nothing until the end. Watch `read_bytes` in
`/proc/$(systemctl show btrfs-convert -p MainPID --value)/io` for progress.
The old ext4 survives as `ext2_saved/image`; `btrfs-convert -r /dev/pool/root`
restores it until that subvolume is deleted.

### 4. Build the subvolume layout

Copy this script to the installer as `/root/subvols.sh` and run it with
`systemd-run --unit=btrfs-subvols --property=Type=exec
--setenv=PATH=/run/current-system/sw/bin /root/subvols.sh`. It snapshots the
top level as `@root`, reflink-copies `/nix`, `/home` and `/var/lib` into their
own subvolumes, and empties an original only after a full listing of the copy
matches it. On framework it took 8.5 minutes.

```bash
#!/usr/bin/env bash
set -euo pipefail
T=/mnt/top

log() { echo "[$(date +%T)] $*"; }
listing() { (cd "$1" && find . -mindepth 1 -printf '%P\t%y\t%s\t%m\t%U\t%G\t%l\n' | LC_ALL=C sort | md5sum | cut -d' ' -f1); }

mkdir -p "$T"
mountpoint -q "$T" && umount "$T"
mount -o subvolid=5 /dev/pool/root "$T"

[ -e "$T/@root" ] && { log "@root already exists, refusing to continue"; exit 1; }

btrfs subvolume snapshot "$T" "$T/@root"
# The nested ext2_saved subvolume shows up as an empty directory in the snapshot.
rmdir "$T/@root/ext2_saved"

for pair in nix:@nix home:@home var/lib:@var-lib; do
  dir=${pair%%:*}
  sub=${pair#*:}
  src="$T/@root/$dir"
  dst="$T/$sub"
  btrfs subvolume create "$dst"
  cp -a --reflink=always "$src/." "$dst/"
  [ "$(listing "$src")" = "$(listing "$dst")" ] || { log "MISMATCH for $dir, stopping"; exit 1; }
  find "$src" -mindepth 1 -delete
done

btrfs subvolume create "$T/@snapshots"
mkdir -p "$T/@root/.snapshots"
btrfs subvolume list "$T"
```

### 5. Switch the config and install the new generation

Set `filesystem = "btrfs";` on the host in `flake/hosts.nix`, commit, and
build on t14:

```sh
SYS=$(nix build --no-link --print-out-paths .#nixosConfigurations.HOST.config.system.build.toplevel)
```

Mount the layout on the installer exactly as the config lists it:

```sh
ssh iso 'umount /mnt/top; O=compress=zstd,noatime
  mount -o $O,subvol=@root /dev/pool/root /mnt
  for p in nix:@nix home:@home var/lib:@var-lib .snapshots:@snapshots; do
    mkdir -p /mnt/${p%%:*}; mount -o $O,subvol=${p#*:} /dev/pool/root /mnt/${p%%:*}
  done
  mkdir -p /mnt/boot; mount -o umask=0077 /dev/disk/by-partlabel/disk-main-ESP /mnt/boot'
```

Copy the system into the host's own store, then install it. Most paths are
already there, so only the difference travels:

```sh
nix copy --no-check-sigs --to "ssh://iso?remote-store=local?root=/mnt" "$SYS"
ssh iso "nixos-install --system $SYS --root /mnt --no-root-passwd --no-channel-copy"
ssh iso 'sync; umount -R /mnt'
```

`nixos-install` here only adds a generation and installs systemd-boot with it
as the default. It does not reformat or touch `/home`. The signing hook in
`disk-tpm-encryption.nix` signs the boot files with the keys in
`/var/lib/sbctl`, and skips TPM enrollment because the password file is gone.
Warnings about `/etc/static` existing and GDM greeter UIDs are expected.

### 6. Boot

1. Remove the stick and boot with Secure Boot still off. Expect a LUKS
   passphrase prompt, since the TPM seal includes PCR 7.
2. Check `lsblk -o NAME,FSTYPE,MOUNTPOINTS`: `pool-root` is `btrfs` with `/`,
   `/nix`, `/home`, `/var/lib` and `/.snapshots`.
3. Turn Secure Boot back on and boot. If it still asks for the passphrase, run
   `nix run .#reenroll-tpm HOST` from t14.
4. Desktops log back into the Netbird tray before `ssh HOST` works.

### 7. Clean up

Only once the host works, since this ends the rollback:

```sh
sudo mount -o subvolid=5 /dev/pool/root /mnt
ls /mnt    # @root @nix @home @var-lib @snapshots ext2_saved plus old dirs
sudo btrfs subvolume delete /mnt/ext2_saved
sudo nix shell nixpkgs#e2fsprogs -c chattr -i /mnt/var/empty
cd /mnt && sudo find . -mindepth 1 -maxdepth 1 ! -name '@*' -exec rm -rf {} +
ls /mnt    # only the five @ subvolumes
cd / && sudo umount /mnt
for u in 30 60 80; do sudo btrfs balance start -dusage=$u /; done
sudo btrfs balance start -f -mconvert=dup,soft -sconvert=dup,soft /
sudo btrfs scrub start -B /
```

The old top-level directories share their data with the subvolumes, so
removing them deletes nothing in use; check the `ls` first anyway. NixOS
marks `/var/empty` immutable, and `chattr` comes from nixpkgs because
e2fsprogs is no longer on the PATH of a btrfs host. The `rm` still walks the
whole old tree and took several minutes on framework.

Removing the old tree leaves the data chunks partly empty while nearly the
whole device stays allocated. On t14 the metadata conversion then stopped with
`No space left on device`, because DUP metadata needs new chunks from
unallocated space. The `-dusage` passes compact the data chunks first and hand
the emptied ones back. The conversion leaves metadata and system `single`, and
the last balance gives them the two copies a freshly made btrfs has. Changing
the system profile needs `-f`, and `soft` skips chunks already converted, so
the step can be rerun after an interruption.

## Pitfalls met on the first run

- Installers built before "iso: Drop the second definition of the Netbird
  setup key" carry the key twice and fail enrollment with `invalid uuid length
  73`. Before "iso: Make the installer's host key usable by sshd and agenix"
  their SSH host key does not load, so sshd falls back to a generated RSA key.
- Editing `~/.ssh/known_hosts` with `sudo` leaves it owned by root, and ssh
  then fails with `hostkeys_foreach failed ... Permission denied`.
- `add-ssh-key` writes the config entry without `IdentitiesOnly yes`; with
  several keys in the agent the host then disconnects with `Too many
  authentication failures`. The key only works once it is on `main` on GitHub,
  since hosts fetch authorized keys from there.
