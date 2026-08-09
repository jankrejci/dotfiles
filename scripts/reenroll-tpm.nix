# Re-seal the LUKS TPM key against the current PCR values
#
# - dbx, secure boot key, and firmware updates change PCR0 or PCR7, which
#   invalidates the sealed policy and drops the host back to passphrase boot
# - the on-host enroll-tpm-key service cannot repair this, its one time
#   password file is shredded right after the install time enrollment
# - usage: nix run .#reenroll-tpm hostname
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "reenroll-tpm";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
    gnugrep
    iputils
    jq
    nix
    openssh
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="nb.krejci.io"
    readonly MAPPER_NAME="crypted"
    # Must match the PCR set sealed by modules/disk-tpm-encryption.nix
    readonly PCRS="0,7"

    # Set once in main. A host cannot ssh to itself here, the loopback
    # connection trips host key verification, and laptops are re-sealed from
    # their own console anyway.
    IS_LOCAL=false

    function on_target() {
      local -r target="$1"
      shift

      [ "$IS_LOCAL" = true ] && {
        sudo "$@"
        return
      }
      # shellcheck disable=SC2029 # the command is ours, it expands client side by design
      ssh "$target" sudo "$@"
    }

    # Same as on_target but with a terminal, systemd-cryptenroll prompts for the
    # passphrase of the recovery slot before it can add the new TPM slot. Kept
    # as a copy rather than parameterizing the ssh options, which would need an
    # unquoted expansion and a shellcheck suppression to save two lines.
    function on_target_tty() {
      local -r target="$1"
      shift

      [ "$IS_LOCAL" = true ] && {
        sudo "$@"
        return
      }
      # shellcheck disable=SC2029 # the command is ours, it expands client side by design
      ssh -t "$target" sudo "$@"
    }

    # Resolve the backing partition from the running mapping rather than
    # repeating the by-partlabel path from the module, which would silently
    # drift the day a host is installed on a different layout.
    function luks_device() {
      local -r target="$1"
      on_target "$target" cryptsetup status "$MAPPER_NAME" 2>/dev/null |
        gawk '/device:/{print $2}'
    }

    function reenroll() {
      local -r target="$1"
      local -r device="$2"

      info "Re-sealing TPM key for $device against PCR$PCRS"
      warn "The LUKS passphrase is required to authorize this"

      on_target_tty "$target" systemd-cryptenroll \
        --wipe-slot=tpm2 \
        --tpm2-device=auto \
        "--tpm2-pcrs=$PCRS" \
        "$device" || {
        error "TPM enrollment failed, the passphrase slot is untouched"
        exit 1
      }
    }

    function verify_slots() {
      local -r target="$1"
      local -r device="$2"

      local slots
      slots=$(on_target "$target" systemd-cryptenroll "$device") || {
        error "Failed to list key slots on $device"
        exit 1
      }

      grep -q tpm2 <<< "$slots" || {
        error "No tpm2 slot present after enrollment"
        exit 1
      }

      grep -q password <<< "$slots" || {
        warn "No password slot left, the TPM is now the only way in"
      }

      info "Key slots after enrollment:"
      echo "$slots" >&2
    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$DOMAIN"

      [ "$hostname" = "$(uname -n)" ] && {
        IS_LOCAL=true
        info "Target is this machine, running without ssh"
      }

      [ "$IS_LOCAL" = true ] || require_ssh_reachable "$target"

      local -r device=$(luks_device "$target")
      [ -n "$device" ] || {
        error "No backing device found for mapping '$MAPPER_NAME' on $hostname"
        info "Is this host using modules/disk-tpm-encryption.nix?"
        exit 1
      }
      info "LUKS device on $hostname is $device"

      reenroll "$target" "$device"
      verify_slots "$target" "$device"

      info "TPM key re-sealed against current PCRs"
      info "Reboot $hostname to confirm it unlocks without the passphrase"
    }

    main "$@"
  '';
}
