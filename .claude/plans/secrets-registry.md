# Secrets Management Plan

## Problem

Current state:
- Ad-hoc injection scripts for each secret type
- Secrets live only on hosts, no audit trail
- sops-nix in flake inputs but module not used
- Comments say "via sops-nix" but actually manual SSH injection
- No per-host isolation: compromised host could expose other hosts' secrets

## Solution: agenix-rekey

agenix-rekey extends agenix with automatic rekeying using a master identity.
vaultix was also considered but agenix-rekey was chosen for its built-in generators
and more mature ecosystem.

Security model:
1. Master identity on deploy machine only (encrypted laptops)
2. Secrets encrypted with master key in git (audit trail)
3. Automatic rekeying: per-host copies encrypted for each host's SSH key
4. Host compromise exposes only that host's secrets

Templates not needed: Dex, Grafana, ntfy all support `secretFile` or env vars natively.

## Architecture

```
Master Identity (age key on encrypted deploy laptops)
        |
        v
   secrets/*.age  (master-encrypted, in git)
        |
        |  -- agenix rekey -a --
        |
        v
   secrets/rekeyed/<host>/  (host-encrypted, in git)
        |
        |  -- nixos-rebuild --
        |
        v
   /run/agenix/<name>  (decrypted at boot via systemd)
```

### Storage Mode

Using local storage mode: rekeyed secrets stored in `secrets/rekeyed/<host>/`
and committed to git. The main advantage is builds work without master key access,
making CI and team collaboration straightforward.

Derivation mode was considered but adds complexity without benefit for a private repo.

### Host Key Configuration

agenix-rekey accepts SSH Ed25519 pubkeys directly (no ssh-to-age conversion needed):

```bash
# Get host's SSH pubkey
ssh-keyscan -t ed25519 hostname 2>/dev/null

# Add to host config (SSH format works directly)
age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
```

### Host Key Bootstrap

**Option A: Pre-generate key (recommended)**

```bash
# 1. Generate host key locally
ssh-keygen -t ed25519 -f /tmp/ssh_host_ed25519_key -N ""

# 2. Add SSH pubkey to host config
age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";

# 3. Encrypt private key with master identity
agenix edit secrets/hosts/newhost-ssh-key.age
# Paste contents of /tmp/ssh_host_ed25519_key

# 4. Rekey all secrets for new host
agenix rekey -a

# 5. Commit everything together
git add . && git commit -m "host: Add newhost with secrets"

# 6. Install
nixos-anywhere --flake '.#newhost' root@target-ip
```

Alternatively, agenix-rekey supports dummy pubkeys for initial deploy but this
requires two deploys and is not recommended.

## Flake Configuration

### Flake inputs

```nix
inputs = {
  agenix.url = "github:ryantm/agenix";
  agenix-rekey = {
    url = "github:oddlama/agenix-rekey";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### flake-parts integration

```nix
# flake/default.nix
{inputs, ...}: {
  imports = [
    inputs.agenix-rekey.flakeModule
    # ... other imports
  ];
}

# flake/packages.nix (perSystem)
{
  perSystem = {pkgs, ...}: {
    agenix-rekey.nixosConfigurations = inputs.self.nixosConfigurations;
  };
}
```

### NixOS module configuration

```nix
# In baseModules or common config
({config, lib, ...}: let
  hostName = config.networking.hostName;
  hostPubkeys = {
    myhost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
  };
in {
  age.rekey = {
    # Private key path - absolute to avoid copying into nix store
    masterIdentities = ["~/.age/master.txt"];
    storageMode = "local";
    # Path must use string concatenation, not path literal
    localStorageDir = ../secrets/rekeyed + "/${hostName}";
    hostPubkey = lib.mkIf (hostPubkeys ? ${hostName}) hostPubkeys.${hostName};
  };
})
```

**Critical:**
- `masterIdentities` must point to the **private key**
- Use absolute path to avoid copying private key into nix store
- `localStorageDir` must use `path + "/string"` format

## Rekey Workflow

Commands:
- `agenix edit <file>` - Create or edit secret (opens $EDITOR)
- `agenix rekey` - Re-encrypt secrets for all hosts
- `agenix rekey -a` - Rekey and auto-stage in git
- `agenix generate` - Generate secrets that have generators defined
- `agenix view` - View secrets with fzf picker

Typical workflow:
```bash
# 1. Create/edit secret
agenix edit secrets/my-secret.age

# 2. Add declaration to NixOS config
age.secrets.my-secret = {
  rekeyFile = ../secrets/my-secret.age;
  owner = "service-user";
};

# 3. Rekey for all hosts (auto-stages)
agenix rekey -a

# 4. Commit and deploy
git commit -m "secrets: Add my-secret"
```

Build fails with instructions if rekey needed, making it hard to forget.

## Secret Declaration

```nix
age.secrets.example = {
  rekeyFile = ../secrets/example.age;  # Master-encrypted source
  owner = "service-user";
  group = "service-group";
  mode = "0400";
};

# For secrets needed before user creation
age.secrets.password-hash = {
  rekeyFile = ../secrets/password.age;
  neededForUsers = true;  # Decrypts to /run/secrets-for-users/
};
```

### Predefined Generators

agenix-rekey includes these generators:
- `alnum` - 48-character alphanumeric
- `base64` - 32-byte base64 (length 44)
- `hex` - 24-byte hexadecimal (length 48)
- `passphrase` - 6-word passphrase
- `dhparams` - 4096-bit DH parameters
- `ssh-ed25519` - ED25519 SSH private key

Usage:
```nix
# Define custom generator
age.generators.my-token = {pkgs, ...}: ''
  echo -n "tk_$(${pkgs.pwgen}/bin/pwgen -s 29 1)"
'';

# Use generator in secret
age.secrets.my-token = {
  rekeyFile = ../secrets/my-token.age;
  generator.script = "my-token";  # Reference by name
};

# Or use predefined generator
age.secrets.random-password = {
  rekeyFile = ../secrets/random-password.age;
  generator.script = "alnum";
};
```

Run `agenix generate` to create secrets with generators defined.

## Service-Specific Configuration

### Dex (OAuth Provider)

```nix
services.dex.settings.staticClients = [{
  id = "grafana";
  secretFile = config.age.secrets.grafana-client-secret.path;
}];

# Google OAuth via EnvironmentFile
systemd.services.dex.serviceConfig.EnvironmentFile =
  config.age.secrets.google-oauth-env.path;
```

### Grafana

```nix
services.grafana.settings.auth.generic_oauth = {
  client_id = "grafana";
  client_secret = "$__file{${config.age.secrets.dex-client-secret.path}}";
};
```

### ACME (Cloudflare)

```nix
age.secrets.cloudflare-api-token = {
  rekeyFile = ../secrets/cloudflare-api-token.age;
  owner = "acme";
};

security.acme.defaults.environmentFile = config.age.secrets.cloudflare-api-token.path;
```

### User Password Hashes

```nix
age.secrets.jkr-password-hash = {
  rekeyFile = ../secrets/jkr-password.age;
  neededForUsers = true;
};

users.users.jkr = {
  hashedPasswordFile = config.age.secrets.jkr-password-hash.path;
};
```

### Shared Secrets

Same source file, declared on each host:

```nix
# On dex host
age.secrets.grafana-client-secret = {
  rekeyFile = ../secrets/dex-grafana-secret.age;
  owner = "dex";
};

# On grafana host
age.secrets.grafana-client-secret = {
  rekeyFile = ../secrets/dex-grafana-secret.age;
  owner = "grafana";
};
```

Rekeying produces separate encrypted copies for each host.

## Implementation Phases

### Phase 1: Tool Setup

1. Add agenix and agenix-rekey to flake inputs
2. Import flakeModule in flake/default.nix
3. Add perSystem agenix-rekey config in flake/packages.nix
4. Add agenix modules to baseModules
5. Configure masterIdentities path
6. Configure storageMode = "local" and localStorageDir
7. Add hostPubkey for each host (ssh-keyscan existing hosts)

### Phase 2: Migrate Static Secrets

Start with secrets that don't need generation:
1. Cloudflare API token
2. Google OAuth credentials
3. Dex client secrets (generate once, store)
4. User password hashes

For each:
1. Extract current value from host or create new
2. Create encrypted file: `agenix edit secrets/name.age`
3. Add declaration to service module
4. Update service to use `config.age.secrets.name.path`
5. Run `agenix rekey -a`
6. Test deploy
7. Remove old injection script usage

### Phase 3: Generated Secrets

Add generators for:
1. ntfy tokens (per-service)
2. Random passwords where needed

### Phase 4: Cleanup

1. Remove old injection scripts
2. Update documentation

## Migration Notes

### What Changes

- Secrets stored encrypted in git (audit trail)
- Run `agenix rekey -a` before deploy when secrets change
- Services reference `/run/agenix/` paths

### What Stays Same

- Service configs mostly unchanged (just path updates)
- Deploy workflow: still `deploy-config` or `nixos-rebuild`
- Dex, Grafana, etc. already support file-based secrets

### Rollback Plan

Keep old injection scripts until new system proven. Both can coexist:
- Old scripts write to `/var/lib/*/secrets/`
- New system writes to `/run/agenix/`
- Update service paths one at a time
