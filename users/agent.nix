# Unprivileged account for running agent processes under
#
# - system account, so it stays off the GDM user list
# - no home directory and no login shell
# - jkr shares the agent group and may run commands as agent without a password
{pkgs, ...}: {
  users.users = {
    agent = {
      # A system account rather than a normal one. AccountsService hides users
      # below uid 1000 from the greeter, which is what keeps this off the login
      # screen, and it also skips home directory creation.
      isSystemUser = true;
      group = "agent";

      # Deliberately not pinned, unlike the human accounts. System uids come
      # from a range nixpkgs also assigns static ids out of, so a hand picked
      # number here risks colliding with a service added later.

      # Nothing ever logs in as this account, it is only entered through sudo.
      # sshd rejects a nologin shell regardless of what keys it is offered,
      # which closes ssh without depending on the key server omitting the user.
      shell = "${pkgs.shadow}/bin/nologin";
    };
  };

  users.groups.agent = {
    # agent itself is a member through its primary group above. jkr joins as a
    # supplementary member so files the agent writes stay readable to both.
    members = ["jkr"];
  };

  # Running work as agent is the whole point of the account, so prompting jkr
  # for a password on every invocation would only train the prompt away.
  # Scoped to this one target user, not a blanket sudo grant.
  #
  # Redundant today, since common.nix sets wheelNeedsPassword to false and jkr
  # is in wheel, which already grants every target user without a password.
  # Kept because it states the one grant this account actually needs, so the
  # agent workflow survives wheel being tightened later.
  security.sudo.extraRules = [
    {
      users = ["jkr"];
      runAs = "agent";
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
