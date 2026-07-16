---
paths:
  - "homelab/**/*"
---

# Homelab Service Module Conventions

Authoring conventions for service modules under `homelab/`. These load only
when working under `homelab/`.

**Adding a new service:**
1. Read existing modules for patterns: `redis.nix` (simple), `jellyfin.nix` (nginx), `grafana.nix` (database)
2. Create `homelab/myservice.nix` following the `homelab.X.enable` pattern
3. Add to `homelab/default.nix` imports in alphabetical order
4. Enable in host definition in `flake/hosts.nix`

**Service rules:**
- Bind to `127.0.0.1` by default, never `0.0.0.0`
- Use `lib.mkIf cfg.enable` for all config
- Every port is a `lib.types.port` option named `port` or `port.<name>`; see
  the Port and IP Patterns section in `CLAUDE.md` for the collision-check rules

**Common integration patterns used across modules:**
- `homelab.healthChecks` -- `systemctl is-active` or HTTP check with timeout
- `homelab.scrapeTargets` -- prometheus job name and metricsPath
- `homelab.backup.jobs` -- restic paths and pre/post hooks
- nginx reverse proxy -- `forceSSL`, `useACMEHost`, `proxyPass` to `127.0.0.1:PORT`
- See `vaultwarden.nix` for a module using all four patterns
