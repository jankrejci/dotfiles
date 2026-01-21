# Secrets Management Plan

## Problem

Current state:
- Ad-hoc injection scripts for each secret type
- Secrets live only on hosts, no audit trail
- sops-nix in flake inputs but module not used
- Comments say "via sops-nix" but actually manual SSH injection
- No per-host isolation: compromised host could expose other hosts' secrets

## Solution: agenix-rekey or vaultix

Both tools implement the same security model:
1. Master identity on deploy machine only (encrypted laptops)
2. Secrets encrypted with master key in git (audit trail)
3. Automatic rekeying: per-host copies encrypted for each host's SSH key
4. Host compromise exposes only that host's secrets

### Tool Comparison

| Feature | vaultix | agenix-rekey |
|---------|---------|--------------|
| Generators | Manual only | Built-in (random, hex, ssh keys) |
| flake-parts | Native | Works, more wiring |
| Maturity | Newer | More established |
| Multiple master keys | extraRecipients | Native list |
| Hashed passwords | beforeUserborn | neededForUsers |
| Shared secrets | Declare on each host | Declare on each host |
| Host key bootstrap | ssh-keyscan or dummy | ssh-keyscan or dummy |

Templates not needed: Dex, Grafana, ntfy all support `secretFile` or env vars natively.

### Recommendation

**agenix-rekey** because:
- Generators for random tokens (ntfy, passwords)
- More mature and battle-tested
- Native multiple master keys support

Both tools work similarly otherwise. vaultix is fine if flake-parts integration matters more.

## Architecture

```
Master Identity (age key on encrypted deploy laptops)
        │
        ▼
   secrets/*.age  (master-encrypted, in git)
        │
        │  ── agenix rekey / nix run .#renc ──
        │
        ▼
   secrets/rekeyed/<host>/  or  secrets/cache/<host-hash>/
        │
        │  ── nixos-rebuild ──
        │
        ▼
   /run/secrets/<name>  (decrypted at boot via systemd)
```

### How Host Keys Become Age Keys

agenix/vaultix use `ssh-to-age` to derive age keys from SSH Ed25519 host keys:

1. SSH Ed25519 keys use Edwards curve (signing)
2. Age uses X25519 curve (encryption)
3. `ssh-to-age` converts Ed25519 → X25519 via standard cryptographic transform
4. Host's `/etc/ssh/ssh_host_ed25519_key` becomes decryption key at boot

To add a host to the rekey configuration:
```bash
# Get host's SSH pubkey
ssh-keyscan -t ed25519 hostname 2>/dev/null | grep ed25519

# Convert to age pubkey
ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# Output: age1...

# Add to host config
age.rekey.hostPubkey = "age1...";
```

### Host Key Bootstrap

Options for new hosts:

**Option A: Host key as managed secret (recommended)**

Store the host private key encrypted in the repo. It's just another secret managed by agenix:

```bash
# 1. Generate host key locally
ssh-keygen -t ed25519 -f /tmp/ssh_host_ed25519_key -N ""

# 2. Convert to age pubkey for host config
ssh-to-age < /tmp/ssh_host_ed25519_key.pub
# Add output to age.rekey.hostPubkey in host config

# 3. Encrypt private key with master identity
agenix edit secrets/hosts/newhost-ssh-key.age
# Paste contents of /tmp/ssh_host_ed25519_key

# 4. Rekey all secrets for new host
agenix rekey

# 5. Commit everything together
git add . && git commit -m "host: Add newhost with secrets"

# 6. Install (key decrypted and placed by agenix)
nixos-anywhere --flake '.#newhost' root@target-ip
```

Benefits:
- Everything prepared before install, no commits during deploy
- Key rotation is just re-encrypt and rekey
- Consistent with how other secrets are managed
- Host key becomes auditable in git history

The host key secret needs special handling in NixOS config:
```nix
age.secrets.ssh-host-key = {
  rekeyFile = ./secrets/hosts/${config.networking.hostName}-ssh-key.age;
  path = "/etc/ssh/ssh_host_ed25519_key";
  mode = "0600";
  # Decrypt early so sshd starts correctly
};
```

**Option B: Dummy pubkey then update**

Use agenix-rekey's dummy pubkey for initial deploy. Requires two deploys: first boot
has failing secrets, then update with real pubkey from `ssh-keyscan`. Only use this
if you can't pre-generate keys for some reason.

### Shared Secrets

Same source file, declared on each host that needs it:

```nix
# secrets/dex-grafana-secret.age (master-encrypted)

# On dex host
age.secrets.grafana-client-secret = {
  rekeyFile = ./secrets/dex-grafana-secret.age;
  owner = "dex";
};

# On grafana host
age.secrets.grafana-client-secret = {
  rekeyFile = ./secrets/dex-grafana-secret.age;
  owner = "grafana";
};
```

Rekeying produces separate encrypted copies for each host.

## Service-Specific Configuration

### Dex (OAuth Provider)

Already supports declarative secrets via `secretFile`:

```nix
services.dex.settings.staticClients = [{
  id = "grafana";
  secretFile = config.age.secrets.grafana-client-secret.path;
}];

# Google OAuth via EnvironmentFile
systemd.services.dex.serviceConfig.EnvironmentFile =
  config.age.secrets.google-oauth-env.path;
```

No changes needed to dex.nix structure, just point paths to agenix/vaultix secrets.

### ntfy (Notifications)

Declarative token management via Nix options and preStart script:

```nix
# Generate tokens with agenix-rekey
age.generators.ntfy-token = { pkgs, ... }: ''
  echo -n "tk_$(${pkgs.pwgen}/bin/pwgen -s 29 1)"
'';

# Per-service token secrets
age.secrets.ntfy-grafana-token = {
  rekeyFile = ./secrets/ntfy-grafana-token.age;
  generator.script = "ntfy-token";
  owner = "ntfy-sh";
};
age.secrets.ntfy-alertmanager-token = {
  rekeyFile = ./secrets/ntfy-alertmanager-token.age;
  generator.script = "ntfy-token";
  owner = "ntfy-sh";
};
```

Declarative user/ACL config in Nix, tokens from secrets:

```nix
# Declare services and their permissions in Nix
homelab.ntfy.clients = {
  grafana = {
    tokenFile = config.age.secrets.ntfy-grafana-token.path;
    topics = [ "alerts-grafana" ];
    permissions = "rw";
  };
  alertmanager = {
    tokenFile = config.age.secrets.ntfy-alertmanager-token.path;
    topics = [ "alerts" ];
    permissions = "rw";
  };
  prusa = {
    tokenFile = config.age.secrets.ntfy-prusa-token.path;
    topics = [ "alerts-prusa" ];
    permissions = "wo";  # write-only, no read
  };
};
```

The module generates a preStart script that:
1. Creates users with random passwords (ntfy requires users for token ownership)
2. Assigns tokens to users (read from secret files)
3. Sets per-topic ACL based on declared permissions

This keeps all config in Nix while tokens stay in age secrets. Per-topic ACL limits
blast radius: compromised RPi can only spam its own topic.

### Grafana

Supports `$__file{}` syntax:

```nix
services.grafana.settings.auth.generic_oauth = {
  client_id = "grafana";
  client_secret = "$__file{${config.age.secrets.dex-client-secret.path}}";
};
```

### User Password Hashes

Use `neededForUsers` for secrets required before user creation:

```nix
age.secrets.jkr-password-hash = {
  rekeyFile = ./secrets/jkr-password.age;
  neededForUsers = true;  # Decrypts to /run/secrets-for-users/
};

users.users.jkr = {
  hashedPasswordFile = config.age.secrets.jkr-password-hash.path;
};
```

No userborn/sysusers needed.

### Borg Passphrase

Same secret on both server and client:

```nix
# Shared source
# secrets/borg-passphrase.age

# On backup server
age.secrets.borg-passphrase = {
  rekeyFile = ./secrets/borg-passphrase.age;
  owner = "root";
};

# On backup client
age.secrets.borg-passphrase = {
  rekeyFile = ./secrets/borg-passphrase.age;
  owner = "root";
};
```

### Cloudflare API Token

Manual input, no generator:

```nix
age.secrets.cloudflare-api-token = {
  rekeyFile = ./secrets/cloudflare-api-token.age;
  owner = "acme";
};
```

Create with `agenix edit secrets/cloudflare-api-token.age` and paste token.

## Implementation Phases

### Phase 1: Tool Setup

1. Choose agenix-rekey or vaultix
2. Add to flake inputs, import module
3. Configure master identity path
4. Set up `.sops.yaml` or equivalent for host keys

### Phase 2: Migrate Static Secrets

Start with secrets that don't need generation:
1. Cloudflare API token
2. Google OAuth credentials
3. Dex client secrets (generate once, store)
4. User password hashes

For each:
1. Create encrypted file: `agenix edit secrets/name.age`
2. Add declaration to host config
3. Update service to use `config.age.secrets.name.path`
4. Test deploy
5. Remove old injection script usage

### Phase 3: Generated Secrets

Add generators for:
1. ntfy tokens (per-service)
2. Random passwords where needed

### Phase 4: Cleanup

1. Remove old injection scripts
2. Update documentation
3. Remove sops.yaml if not using sops-nix

## Related Plans

- **Scripts refactor**: See `.claude/plans/scripts-refactor.md` for splitting `scripts.nix`
  into modular files. Injection scripts will be removed after secrets migration.

## Migration Notes

### What Changes

- Secrets stored encrypted in git (audit trail)
- Rekeying step on deploy machine before deploy
- Services reference `/run/secrets/` or `/run/agenix/` paths

### What Stays Same

- Service configs mostly unchanged (just path updates)
- Deploy workflow: still `deploy-config` or `nixos-rebuild`
- Dex, Grafana, etc. already support file-based secrets

### Rollback Plan

Keep old injection scripts until new system proven. Both can coexist:
- Old scripts write to `/var/lib/*/secrets/`
- New system writes to `/run/secrets/`
- Update service paths one at a time
