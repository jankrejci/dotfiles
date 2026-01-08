# SSO Implementation Research

Research findings for implementing Single Sign-On in the homelab.

## Overview

### What is SSO/OIDC?

**SSO (Single Sign-On):** Log in once, access many apps. Instead of separate passwords for Immich, Grafana, Memos - you log in once and all apps recognize you.

**OIDC (OpenID Connect):** A standard protocol for proving identity. When Immich asks "who is this user?", OIDC is the language they speak to get the answer.

### Why an Identity Broker?

Without a broker, each app talks directly to Google:
- 3 separate Google OAuth apps needed
- 3 separate logins
- No central control

With a broker (Dex/Zitadel/Authentik):
```
Immich  ──┐
Grafana ──┼──► Identity Broker ──► Google
Memos   ──┘
```
- 1 Google OAuth app
- 1 login for all apps
- Central user/policy management
- Disable a user once, they lose access everywhere

### Authentication Flow

```
User clicks "Login" on Immich
         ↓
Immich redirects to Identity Broker
         ↓
Broker shows: "Sign in with Google"
         ↓
User authenticates with Google
         ↓
Google tells Broker: "This is user@gmail.com"
         ↓
Broker tells Immich: "This is user@gmail.com, here's their session"
         ↓
User is logged into Immich
         ↓
Later: visit Grafana → Broker already knows you → instant login
```

## Identity Provider Research

### Proton as IdP: NOT POSSIBLE

Proton does not expose OAuth/OIDC endpoints for external applications. There is no "Sign in with Proton" capability.

- Community requested since 2020 (253 votes) - no official response
- Proton SSO only works in reverse: external IdPs authenticate INTO Proton services

**Workaround:** SimpleLogin (Proton-owned) has OAuth, but lacks WebFinger support which breaks some services. Not recommended as primary IdP.

Sources:
- https://protonmail.uservoice.com/forums/945460-general-ideas/suggestions/40659877-sign-in-log-in-with-proton-like-oauth-2-0
- https://protonmail.uservoice.com/forums/945460-general-ideas/suggestions/47641541-proton-identity-sso-idp

## Solution Comparison

### Evaluated Options

| Solution | Google IdP | RAM | NixOS Module | Complexity | Verdict |
|----------|-----------|-----|--------------|------------|---------|
| Authelia | No upstream federation | 20-30MB | Yes | Low | Ruled out - no external IdP |
| Authentik | Yes | 700MB+ | Community flake | High | Risky upgrades, CVEs |
| Keycloak | Yes | 1GB+ | Yes | Very High | Overkill for homelab |
| **Dex** | Yes | ~100MB | Yes | Low | **Selected** |
| Zitadel | Yes | ~512MB | Yes (buggy) | Medium | Good alternative |

### Authentik Issues

- High memory: 700-800MB idle
- Memory leaks documented
- Breaking upgrades: 2024.4.0, 2024.8, 2025.4 all had major issues
- Multiple CVEs in 2024-2025 including critical (9.8)
- No downgrade support

Sources:
- https://github.com/goauthentik/authentik/issues/17869
- https://github.com/goauthentik/authentik/issues/9454

### Dex vs Zitadel

| Aspect | Dex | Zitadel |
|--------|-----|---------|
| Purpose | Lightweight OIDC proxy | Full IAM platform |
| User management | None (proxy only) | Built-in UI |
| MFA | No | Yes (TOTP, Passkeys) |
| Admin UI | No | Yes |
| RAM | ~100MB | ~512MB |
| NixOS module | Stable | PostgreSQL bug reported |
| Config style | YAML (declarative) | Web UI |
| Adding users | Upstream IdP only | Web UI or API |

**Decision: Dex** - simpler, lighter, no known NixOS bugs. Can migrate to Zitadel later if user management becomes a pain point.

## Dex Configuration

### Supported Identity Providers

| Provider | Status |
|----------|--------|
| Google | Alpha |
| GitHub | Stable |
| GitLab | Beta |
| Microsoft/Entra | Beta |
| LDAP | Stable |
| SAML | Unmaintained (avoid) |
| Generic OIDC | Beta |

### NixOS Module

```nix
services.dex = {
  enable = true;
  settings = {
    issuer = "https://dex.example.com";
    storage = {
      type = "postgres";
      config.host = "/run/postgresql";
    };
    web.http = "127.0.0.1:5556";
    connectors = [{
      type = "google";
      id = "google";
      name = "Google";
      config = {
        clientID = "$GOOGLE_CLIENT_ID";
        clientSecret = "$GOOGLE_CLIENT_SECRET";
        redirectURI = "https://dex.example.com/callback";
      };
    }];
    staticClients = [
      {
        id = "immich";
        name = "Immich";
        redirectURIs = [
          "https://immich.example.com/auth/login"
          "https://immich.example.com/user-settings"
          "app.immich:///oauth-callback"
        ];
        secretFile = "/run/secrets/dex-immich-secret";
      }
      {
        id = "grafana";
        name = "Grafana";
        redirectURIs = ["https://grafana.example.com/login/generic_oauth"];
        secretFile = "/run/secrets/dex-grafana-secret";
      }
      {
        id = "memos";
        name = "Memos";
        redirectURIs = ["https://memos.example.com/auth/callback"];
        secretFile = "/run/secrets/dex-memos-secret";
      }
    ];
  };
};
```

## Service Integration

### Configuration Methods

| Service | Nix Config | Method |
|---------|-----------|--------|
| Immich | Yes | JSON config file via `IMMICH_CONFIG_FILE` |
| Memos | No | Web UI only (feature requested) |
| Grafana | Yes | Native NixOS options |

### Immich

Supports JSON config file with full OAuth settings:

```json
{
  "oauth": {
    "enabled": true,
    "issuerUrl": "https://dex.example.com",
    "clientId": "immich",
    "clientSecret": "secret-here",
    "scope": "openid email profile",
    "buttonText": "Login with SSO",
    "autoRegister": true,
    "mobileOverrideEnabled": true,
    "mobileRedirectUri": "app.immich:///oauth-callback"
  }
}
```

Set via environment:
```nix
services.immich.environment.IMMICH_CONFIG_FILE = "/var/lib/immich/config.json";
```

**Note:** clientSecret in file requires SOPS encryption or envsubst templating.

Sources:
- https://docs.immich.app/install/config-file/
- https://docs.immich.app/administration/oauth/

### Memos

SSO configuration via environment variables is NOT supported. Must configure via web UI after deployment.

Open feature request from NixOS user: https://github.com/usememos/memos/issues/5004

**Workaround:** Configure SSO via Settings → Identity Providers after first deploy. Config persists in database.

### Grafana

Fully supported via NixOS options:

```nix
services.grafana.settings."auth.generic_oauth" = {
  enabled = true;
  name = "Dex";
  client_id = "grafana";
  client_secret = "$__file{/run/secrets/grafana-oauth-secret}";
  scopes = "openid profile email";
  auth_url = "https://dex.example.com/auth";
  token_url = "https://dex.example.com/token";
  api_url = "https://dex.example.com/userinfo";
  use_pkce = true;
  allow_sign_up = true;
};
```

Sources:
- https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/

## Implementation Difficulty

| Combination | NixOS Setup | Service Config | Overall |
|-------------|-------------|----------------|---------|
| Dex + Immich | Easy | Medium | Medium |
| Dex + Memos | Easy | Easy (but manual) | Easy |
| Dex + Grafana | Easy | Easy | Easy |

## Files to Create/Modify

### New Files
- `homelab/dex.nix` - Dex module (~50-60 lines)
- Secret files for client credentials

### Modified Files
- `homelab/grafana.nix` - Add OAuth config (~15 lines)
- `homelab/immich.nix` - Add config file path (optional)

### No Changes Needed
- `homelab/memos.nix` - Web UI config only

## Future Considerations

### Self-Hosted Netbird

Netbird has embedded Dex since v0.62. When self-hosting Netbird:
- Can use external Dex instance (shared with other services)
- Or use Netbird's embedded Dex for isolation

Zitadel has deeper Netbird integration (JWT group sync) if needed later.

### Migration to Zitadel

If user management becomes painful with Dex:
1. Deploy Zitadel alongside Dex
2. Add Google as identity source in Zitadel
3. Update service OIDC configs to point to Zitadel
4. Decommission Dex

OIDC is standardized - services don't care which broker they use.

## References

### Documentation
- Dex: https://dexidp.io/docs/
- Immich OAuth: https://docs.immich.app/administration/oauth/
- Memos Auth: https://usememos.com/docs/configuration/authentication
- Grafana OAuth: https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/

### NixOS Modules
- services.dex: https://mynixos.com/nixpkgs/option/services.dex.settings
- services.zitadel: https://mynixos.com/options/services.zitadel

### Comparisons
- State of Open-Source Identity 2025: https://www.houseoffoss.com/post/the-state-of-open-source-identity-in-2025-authentik-vs-authelia-vs-keycloak-vs-zitadel
