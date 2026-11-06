---
paths:
  - "homelab/**/*"
  - "modules/**/*"
  - "flake/hosts.nix"
---

# Port and IP Patterns

**Port declaration:** Every port must be a `lib.types.port` option named `port`
or `port.<name>`. Defaults are allowed. Host-specific overrides go in
`flake/hosts.nix`. This naming convention enables a build-time collision check
that enumerates all `port` options across modules.

**Shared service ports** like `services.https.port` and `services.netbird.port.*`
are defined in the `services` attrset in `flake/hosts.nix` and referenced by
modules via `config.homelab.services`.

**IP patterns:**
- `listenAddresses` on nginx vhosts use dummy service IPs from the 192.168.91-92 ranges
- `proxyPass` always uses `127.0.0.1` since the backend service runs on localhost
- These are intentionally different: the service IP is for external routing, localhost is for internal forwarding
