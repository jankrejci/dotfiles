# Borg backup secrets
#
# Provides passphrases for encrypted borg backups. This module enables when any
# backup consumer is enabled. Future backup consumers should add themselves to
# the enable condition.
#
# Passphrases are randomly generated. User should note them down after injection
# in case manual recovery is needed.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab;
in {
  config = lib.mkIf (cfg.immich.enable || cfg.memos.enable) {
    homelab.secrets.borg-passphrase-remote = {
      generate = "token";
      handler = pkgs.writeShellApplication {
        name = "borg-remote-handler";
        text = ''
          install -d -m 700 -o root -g root /root/secrets
          install -m 600 -o root -g root /dev/stdin /root/secrets/borg-passphrase-remote
        '';
      };
    };

    homelab.secrets.borg-passphrase-local = {
      generate = "token";
      handler = pkgs.writeShellApplication {
        name = "borg-local-handler";
        text = ''
          install -d -m 700 -o root -g root /root/secrets
          install -m 600 -o root -g root /dev/stdin /root/secrets/borg-passphrase-local
        '';
      };
    };
  };
}
