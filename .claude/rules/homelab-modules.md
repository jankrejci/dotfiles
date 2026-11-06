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
- The backend binds to localhost even when nginx publishes it. nginx itself
  normally listens on a service IP from `listenAddresses`, but a vhost served
  on the host's own peer name, like `webcam.nix`, or a stream proxy for raw
  TCP, like `serial-bridge.nix`, has no service IP. Such a listener binds all
  addresses and is fenced in by a firewall rule on the Netbird interface plus
  `allow` of the Netbird subnet and `deny all` in nginx
- Use `lib.mkIf cfg.enable` for all config
- Every port is a `lib.types.port` option named `port` or `port.<name>`; see
  `.claude/rules/ports-and-ips.md` for the collision-check rules

**Common integration patterns used across modules:**
- `homelab.healthChecks` -- `systemctl is-active` or HTTP check with timeout
- `homelab.scrapeTargets` -- prometheus job name and metricsPath
- `homelab.backup.jobs` -- restic paths and pre/post hooks
- nginx reverse proxy -- `forceSSL`, `useACMEHost`, `proxyPass` to `127.0.0.1:PORT`
- See `vaultwarden.nix` for a module using all four patterns
