# Homelab Framework Extraction Plan

Goal: prepare the dotfiles codebase for extracting `homelab/` and core `modules/`
into a standalone, reusable NixOS module flake. This branch tackles the easy
preparatory fixes. The actual split into a separate repository is a future step.

## Architecture of the extracted flake

The extracted flake will export NixOS modules. Consumers import and configure:

```nix
# consumer flake.nix
inputs.homelab.url = "github:you/nix-homelab";

# in host config
imports = [ inputs.homelab.nixosModules.default ];
homelab.global.domain = "example.com";
homelab.global.acmeEmail = "admin@example.com";
homelab.immich.enable = true;
homelab.grafana.enable = true;
```

Two roles provided:
- **homelab-server**: services, monitoring, backup (current thinkcenter role)
- **public-proxy**: WG tunnel, signal forwarding, optional borg storage (current vpsfree role)

## Preparatory fixes (this branch)

These eliminate hardcoded values that prevent reuse. Each is a separate commit.

### 1. acme: Derive all values from global.domain

**File:** `homelab/acme.nix`

Currently hardcodes `krejci.io` in 6 places:
- `email = "admin@krejci.io"` (line 35)
- `security.acme.certs."krejci.io"` (line 46)
- `domain = "*.krejci.io"` (line 47)
- `extraDomainNames = ["krejci.io"]` (line 48)
- Alert expr: `acme-krejci.io.service` (line 62)
- Health check: `acme-krejci.io.service` (line 80)

**Fix:** Add `homelab.acme.email` option. Derive cert name, domain, and systemd
unit name from `global.domain`.

### 2. octoprint: Replace hardcoded host reference

**File:** `homelab/octoprint.nix`

Line 56: `allHosts.thinkcenter.homelab.dex.ip` is the only place in any homelab
module that hardcodes a specific hostname.

**Fix:** Add `homelab.octoprint.dexHost` option defaulting to the current host
name. OctoPrint runs on a different machine than Dex, so the consumer must set
this explicitly. The module already has access to `allHosts` so it can look up
the IP dynamically.

### 3. backup: Remove hardcoded default server

**File:** `modules/options.nix`

Line 355: `default = "borg@vpsfree.nb.krejci.io"` bakes in a specific hostname.

**Fix:** Remove the default. Make it a required option when `backup.remote.enable`
is true via an assertion.

### 4. vaultwarden: Add SMTP options

**File:** `homelab/vaultwarden.nix`

Lines 103-108: SMTP host, port, security, from, and username are all hardcoded.

**Fix:** Add `homelab.vaultwarden.smtp` option set with `host`, `port`,
`security`, `from` fields. Default `from` to `"admin@${global.domain}"`.

### 5. desktop: Derive printer domain from global.domain

**File:** `modules/desktop.nix`

Lines 148-189: `brother.krejci.io` hardcoded in CUPS printer setup.

**Fix:** Use `config.homelab.global.domain` to construct the printer domain.
The printer subdomain is already configured via `homelab.printer.subdomain`.

## Future work (not this branch)

These are the hard problems that need architectural changes:

### Secrets across flake boundaries
Every module uses `rekeyFile = ../secrets/foo.age` with paths relative to the
flake. In a library flake these paths don't exist. Each module needs secret path
options so the consumer can point to their own secrets.

### Cross-host evaluation
Prometheus, dashboard, and watchdog iterate `inputs.self.nixosConfigurations`.
The library flake's `self` is wrong. Need a mechanism for consumers to pass their
own nixosConfigurations into the module system.

### Dex client composition
Currently a hardcoded client list. Needs a registry pattern where each service
module registers its own Dex client, similar to `scrapeTargets`.

### Assets
Dashboard icons, grafana dashboards, ntfy templates ship in `../assets/`. Need
to bundle them in the library flake with consumer override support.
