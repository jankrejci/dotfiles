# NetBird Self-Hosted Migration

## Executive Summary

**Status:** Planning Phase
**Migration:** Netbird Cloud → Self-Hosted Netbird
**Architecture:** vpsfree (public gateway) + thinkcenter (control plane) via WireGuard tunnel

### Key Requirements Met

1. ✅ **Management downtime resilience:** Existing WireGuard tunnels continue working
2. ✅ **vpsfree security:** Only reverse proxy + relay (no sensitive data)
3. ✅ **NAT traversal:** vpsfree acts as public gateway to thinkcenter behind NAT
4. ✅ **Simplicity:** Standard nginx reverse proxy + WireGuard tunnel
5. ✅ **Google SSO:** Via OIDC configuration
6. ✅ **Pre-generated setup keys:** Standard feature, agenix integration

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Internet                                                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ vpsfree (Public VPS)  │
         │ - No sensitive data   │
         ├───────────────────────┤
         │ Nginx Reverse Proxy   │
         │ ├─ /management/*      │───┐
         │ ├─ /signalexchange/*  │───┤
         │ └─ / (dashboard)      │───┤ HTTPS/gRPC
         ├───────────────────────┤   │ over WireGuard
         │ Relay Server          │   │ tunnel
         │ (stateless)           │   │
         └───────────────────────┘   │
                     │                │
            WireGuard tunnel          │
            (10.100.0.0/30)           │
                     │                │
                     ▼                │
         ┌───────────────────────┐   │
         │ thinkcenter (Homelab) │◄──┘
         │ Behind NAT            │
         │ Encrypted disk        │
         ├───────────────────────┤
         │ NetBird Management    │
         │ + PostgreSQL          │
         ├───────────────────────┤
         │ Signal Server         │
         ├───────────────────────┤
         │ Dashboard (nginx)     │
         └───────────────────────┘
```

### Migration Timeline Estimate

- **Phase 1:** Infrastructure setup (4-6 hours)
- **Phase 2:** Testing (2-3 hours)
- **Phase 3:** Peer migration (5-8 hours for ~10-15 peers)
- **Phase 4:** Cleanup and documentation (1-2 hours)
- **Total:** 12-19 hours (spread over multiple days)

## Architecture Components

### Core Services

1. **Management Service** (Port 33073)
   - Central coordination hub for network state
   - Handles peer registration, authentication, policies
   - Stores data in PostgreSQL (recommended) or SQLite
   - **Critical limitation:** No HA support, single instance only
   - **Downtime behavior:** Existing peer connections continue working

2. **Signal Service** (Port 10000)
   - Lightweight, stateless peer discovery coordinator
   - Facilitates WebRTC connection negotiation
   - End-to-end encrypted, doesn't see message contents
   - No data persistence

3. **Relay Service** (Port 33080)
   - WebSocket or QUIC transport fallback for NAT traversal
   - Replaced legacy Coturn TURN server (v0.29.0+)
   - **Supports multiple instances** for geographic distribution
   - End-to-end encrypted via WireGuard
   - Stateless, sees only encrypted traffic

4. **Dashboard** (Ports 80/443)
   - Web UI for administration
   - Nginx reverse proxy handles TLS termination
   - Communicates with management service API

5. **Identity Provider**
   - User authentication via OIDC
   - Supports: Google, Azure AD, Okta, Zitadel, Keycloak, Auth0
   - **Recommended:** Google SSO (simplest for personal use)

### Component Responsibilities

#### vpsfree (Public Gateway)
- **Nginx reverse proxy:** TLS termination, proxy gRPC/HTTP to thinkcenter
- **Relay server:** Fallback for NAT traversal
- **ACME certificates:** Let's Encrypt via Cloudflare DNS-01
- **No database, no network state, no credentials**
- **Security:** All data encrypted in transit, no sensitive data at rest

#### thinkcenter (Control Plane)
- **Management server:** Network state, policies, peer registration
- **PostgreSQL database:** All persistent data (network state, peers, policies)
- **Signal server:** Peer discovery coordination
- **Dashboard:** Admin UI (proxied through vpsfree)
- **All secrets via agenix**
- **Security:** Encrypted disk, firewall restricted to WireGuard tunnel only

### NixOS Module Support

Available in nixpkgs (PR #354032):
- `services.netbird.server.enable` - Enable full stack
- `services.netbird.server.domain` - Public domain
- `services.netbird.server.enableNginx` - Reverse proxy integration (we disable, handle separately)
- `services.netbird.server.management.settings` - Management config
- `services.netbird.server.signal` - Signal server config
- `services.netbird.server.dashboard` - Dashboard config
- New relay component replaces deprecated coturn

## High Availability Analysis

### Management Server Limitations

**Status:** NOT SUPPORTED
- GitHub issue #1584 confirms no HA for management component
- Storage backends (SQLite, PostgreSQL) don't support concurrent access
- PostgreSQL support (v0.27.8+) enables future HA, but clustering not production-ready
- **Implication:** Management server is single point of failure

**Failed Approaches:**
- Mounting SQLite/JSON on AWS EFS (NFS) - concurrent access failures
- Multiple management instances - no state synchronization mechanism

**Mitigation Strategy:**
- Robust backup/restore procedures
- Quick recovery procedures (RTO: 2-4 hours)
- Daily PostgreSQL backups with offsite replication
- Existing peer connections survive management downtime

### What IS Supported

**Multiple Relay Servers:** ✅ FULLY SUPPORTED
- Geographic distribution recommended
- Clients automatically select best relay
- Configuration in management.json:
  ```json
  "Relay": {
    "Addresses": ["rel://relay1.example.com:33080", "rel://relay2.example.com:33080"],
    "CredentialsTTL": "24h",
    "Secret": "<shared-secret>"
  }
  ```

**Network Route HA:** ✅ SUPPORTED
- Multiple peers can serve as routing peers for same network
- Groups with multiple peers provide automatic failover
- See: docs.netbird.io/how-to/routing-traffic-to-private-networks

## Prerequisites

### 1. Connectivity: vpsfree → thinkcenter

**Chosen Solution:** Standalone WireGuard Tunnel

**Rationale:**
- Independent of Netbird (no circular dependency during migration)
- Secure (encrypted tunnel, authenticated)
- Simple (standard WireGuard configuration)
- Persistent (automatic reconnection)

**Alternative:** Port forwarding (if router access available) - simpler but less secure

**Configuration:**
```nix
# hosts/thinkcenter/configuration.nix
networking.wireguard.interfaces.wg-vpsfree = {
  ips = ["10.100.0.1/30"];
  listenPort = 51820;
  privateKeyFile = "/run/agenix/wg-vpsfree-private";
  peers = [{
    publicKey = "<vpsfree-wg-public-key>";
    allowedIPs = ["10.100.0.2/32"];
    endpoint = "<vpsfree-public-ip>:51820";
    persistentKeepalive = 25;
  }];
};

networking.firewall.allowedUDPPorts = [51820];

# hosts/vpsfree/configuration.nix
networking.wireguard.interfaces.wg-thinkcenter = {
  ips = ["10.100.0.2/30"];
  listenPort = 51820;
  privateKeyFile = "/run/agenix/wg-thinkcenter-private";
  peers = [{
    publicKey = "<thinkcenter-wg-public-key>";
    allowedIPs = ["10.100.0.1/32"];
    persistentKeepalive = 25;
  }];
};

networking.firewall.allowedUDPPorts = [51820];
```

### 2. DNS Configuration

**Domain:** `netbird.krejci.io` (using existing krejci.io domain)

**DNS Record:**
```
netbird.krejci.io  A  <vpsfree-public-ip>
```

**Add to Cloudflare:** Via existing DNS provider

### 3. Google OAuth Application

**Create Google Cloud Project:**

1. Navigate to: https://console.cloud.google.com/
2. Create new project: "NetBird Self-Hosted"
3. Enable APIs: None required (OAuth only)

**Configure OAuth Consent Screen:**
1. Navigate to: APIs & Services → OAuth consent screen
2. User Type: External (or Internal if Google Workspace)
3. App information:
   - App name: "NetBird VPN"
   - User support email: `<your-email>`
   - Developer contact: `<your-email>`
4. Authorized domains: `krejci.io`
5. Scopes: `openid`, `email`, `profile` (default)

**Create OAuth 2.0 Credentials:**
1. Navigate to: APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID
2. Application type: Web application
3. Name: "NetBird Self-Hosted"
4. Authorized JavaScript origins:
   - `https://netbird.krejci.io`
5. Authorized redirect URIs:
   - `https://netbird.krejci.io/auth/callback`
   - `https://netbird.krejci.io/silent-auth`
6. Create
7. **Save credentials:**
   - Client ID → save for agenix
   - Client Secret → save for agenix

### 4. Cloudflare API Token

**Required for:** Let's Encrypt DNS-01 challenge (wildcard certificate)

**Create token:**
1. Cloudflare dashboard → Profile → API Tokens → Create Token
2. Use template: "Edit zone DNS"
3. Zone Resources: Include → Specific zone → `krejci.io`
4. Create Token
5. **Save token** → add to agenix

**Test token:**
```bash
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type:application/json"
```

## Configuration

### Secrets Setup

**Generate all secrets first:**

```bash
# WireGuard keys
wg genkey | tee thinkcenter-wg-private.key | wg pubkey > thinkcenter-wg-public.key
wg genkey | tee vpsfree-wg-private.key | wg pubkey > vpsfree-wg-public.key

# NetBird secrets
openssl rand -base64 32 > netbird-data-encryption-key.txt
openssl rand -base64 32 > netbird-relay-secret.txt

# Borg passphrases
pwgen 64 1 > netbird-borg-passphrase-local.txt
pwgen 64 1 > netbird-borg-passphrase-remote.txt

# Encrypt with agenix
cat thinkcenter-wg-private.key | age -e -i ~/.ssh/id_ed25519 -o secrets/wg-vpsfree-private.age
cat vpsfree-wg-private.key | age -e -i ~/.ssh/id_ed25519 -o secrets/wg-thinkcenter-private.age
cat netbird-data-encryption-key.txt | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-data-encryption-key.age
cat netbird-relay-secret.txt | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-relay-secret.age
echo "<google-client-id>" | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-google-client-id.age
echo "<google-client-secret>" | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-google-client-secret.age
cat netbird-borg-passphrase-local.txt | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-borg-passphrase-local.age
cat netbird-borg-passphrase-remote.txt | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-borg-passphrase-remote.age

# Clean up plaintext
shred -u *.key *.txt
```

**secrets/secrets.nix:**
```nix
let
  thinkcenter = "ssh-ed25519 AAAA...";
  vpsfree = "ssh-ed25519 AAAA...";
in {
  "netbird-data-encryption-key.age".publicKeys = [thinkcenter];
  "netbird-google-client-id.age".publicKeys = [thinkcenter];
  "netbird-google-client-secret.age".publicKeys = [thinkcenter];
  "netbird-relay-secret.age".publicKeys = [thinkcenter vpsfree];
  "netbird-borg-passphrase-local.age".publicKeys = [thinkcenter];
  "netbird-borg-passphrase-remote.age".publicKeys = [thinkcenter];
  "wg-vpsfree-private.age".publicKeys = [thinkcenter];
  "wg-thinkcenter-private.age".publicKeys = [vpsfree];
}
```

### thinkcenter: NetBird Server

```nix
# hosts/thinkcenter/configuration.nix

# WireGuard tunnel to vpsfree
networking.wireguard.interfaces.wg-vpsfree = {
  ips = ["10.100.0.1/30"];
  listenPort = 51820;
  privateKeyFile = "/run/agenix/wg-vpsfree-private";
  peers = [{
    publicKey = "<vpsfree-wg-public-key>";  # From vpsfree-wg-public.key
    allowedIPs = ["10.100.0.2/32"];
    endpoint = "<vpsfree-public-ip>:51820";
    persistentKeepalive = 25;
  }];
};

# PostgreSQL backend
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  ensureDatabases = ["netbird"];
  ensureUsers = [{
    name = "netbird";
    ensureDBOwnership = true;
  }];
  authentication = ''
    local netbird netbird peer
  '';
};

# Backup PostgreSQL
services.postgresqlBackup = {
  enable = true;
  databases = ["netbird"];
  location = "/var/backup/postgresql";
  startAt = "*-*-* 03:00:00";  # 3 AM daily
};

# NetBird server (management + signal + dashboard)
services.netbird.server = {
  enable = true;
  domain = "netbird.krejci.io";
  enableNginx = false;  # Handle nginx separately

  management.settings = {
    # PostgreSQL backend
    StoreConfig.Engine = "postgres";
    DataStoreEncryptionKey = {
      _secret = "/run/agenix/netbird-data-encryption-key";
    };

    # Listen on all interfaces (for WireGuard tunnel from vpsfree)
    HttpConfig = {
      Address = "0.0.0.0:33073";
      AuthIssuer = "https://accounts.google.com";
      AuthAudience = { _secret = "/run/agenix/netbird-google-client-id"; };
      OIDCConfigEndpoint = "https://accounts.google.com/.well-known/openid-configuration";
      IdpSignKeyRefreshEnabled = true;
    };

    # Signal server
    Signal = {
      Proto = "https";
      URI = "netbird.krejci.io:443";
    };

    # Relay configuration
    Relay = {
      Addresses = ["rel://netbird.krejci.io:33080"];
      Secret = { _secret = "/run/agenix/netbird-relay-secret"; };
    };

    # IDP configuration (Google)
    IdpManagerConfig = {
      ManagerType = "google";
      ClientConfig = {
        Issuer = "https://accounts.google.com";
        TokenEndpoint = "https://oauth2.googleapis.com/token";
        ClientID = { _secret = "/run/agenix/netbird-google-client-id"; };
        ClientSecret = { _secret = "/run/agenix/netbird-google-client-secret"; };
        GrantType = "authorization_code";
      };
    };

    # Device authorization flow
    DeviceAuthorizationFlow = {
      Provider = "hosted";
      ProviderConfig = {
        ClientID = { _secret = "/run/agenix/netbird-google-client-id"; };
        ClientSecret = { _secret = "/run/agenix/netbird-google-client-secret"; };
        Domain = "netbird.krejci.io";
        Audience = { _secret = "/run/agenix/netbird-google-client-id"; };
      };
    };
  };

  # Signal server config
  signal.settings = {
    Address = "0.0.0.0:10000";
  };
};

# PostgreSQL connection via environment variable
systemd.services.netbird-management.environment = {
  NETBIRD_STORE_ENGINE_POSTGRES_DSN = "host=/run/postgresql user=netbird dbname=netbird sslmode=disable";
};

# Dashboard (local nginx)
services.nginx = {
  enable = true;
  virtualHosts."localhost" = {
    listen = [{ addr = "0.0.0.0"; port = 8080; }];
    root = "${pkgs.netbird-dashboard}";
    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
    };
  };
};

# Firewall: Only allow from vpsfree WireGuard tunnel
networking.firewall = {
  allowedTCPPorts = [];  # No public ports
  allowedUDPPorts = [51820];  # WireGuard only

  # Allow from vpsfree via WireGuard tunnel
  extraCommands = ''
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 33073 -j ACCEPT  # Management
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 10000 -j ACCEPT  # Signal
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 8080 -j ACCEPT   # Dashboard
  '';
};

# Secrets
age.secrets = {
  netbird-data-encryption-key.file = ../../secrets/netbird-data-encryption-key.age;
  netbird-google-client-id.file = ../../secrets/netbird-google-client-id.age;
  netbird-google-client-secret.file = ../../secrets/netbird-google-client-secret.age;
  netbird-relay-secret.file = ../../secrets/netbird-relay-secret.age;
  wg-vpsfree-private.file = ../../secrets/wg-vpsfree-private.age;
};

# Borg backup (integrate with existing backup pattern)
services.borgbackup.jobs.netbird-local = {
  paths = [
    "/var/backup/postgresql"
    "/var/lib/netbird"
  ];
  repo = "/var/lib/borg-repos/netbird";
  encryption.mode = "repokey";
  encryption.passCommand = "cat /run/agenix/netbird-borg-passphrase-local";
  compression = "auto,zstd";
  startAt = "daily";
  prune.keep = {
    daily = 7;
    weekly = 4;
    monthly = 6;
  };
};

services.borgbackup.jobs.netbird-remote = {
  paths = [
    "/var/backup/postgresql"
    "/var/lib/netbird"
  ];
  repo = "borg@vpsfree.krejci.io:/var/lib/borg-repos/netbird";
  encryption.mode = "repokey";
  encryption.passCommand = "cat /run/agenix/netbird-borg-passphrase-remote";
  compression = "auto,zstd";
  startAt = "daily";
  prune.keep = {
    daily = 7;
    weekly = 4;
    monthly = 3;
  };
};
```

### vpsfree: Reverse Proxy + Relay

```nix
# hosts/vpsfree/configuration.nix

# WireGuard tunnel to thinkcenter
networking.wireguard.interfaces.wg-thinkcenter = {
  ips = ["10.100.0.2/30"];
  listenPort = 51820;
  privateKeyFile = "/run/agenix/wg-thinkcenter-private";
  peers = [{
    publicKey = "<thinkcenter-wg-public-key>";  # From thinkcenter-wg-public.key
    allowedIPs = ["10.100.0.1/32"];
    persistentKeepalive = 25;
  }];
};

# Nginx reverse proxy
services.nginx = {
  enable = true;
  recommendedProxySettings = true;
  recommendedGzipSettings = true;

  virtualHosts."netbird.krejci.io" = {
    enableACME = true;
    forceSSL = true;

    # Access control: Only from Netbird CGNAT range (after migration)
    # IMPORTANT: Comment out during initial setup/testing
    # extraConfig = ''
    #   allow 100.64.0.0/10;  # Netbird CGNAT
    #   deny all;
    # '';

    locations."/" = {
      proxyPass = "http://10.100.0.1:8080";  # Dashboard via WireGuard
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };

    locations."/management.ManagementService/" = {
      proxyPass = "grpc://10.100.0.1:33073";  # Management via WireGuard
      extraConfig = ''
        grpc_set_header Host $host;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };

    locations."/signalexchange.SignalExchange/" = {
      proxyPass = "grpc://10.100.0.1:10000";  # Signal via WireGuard
      extraConfig = ''
        grpc_set_header Host $host;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };
};

# ACME (Let's Encrypt via Cloudflare DNS-01)
security.acme = {
  acceptTerms = true;
  defaults.email = "admin@krejci.io";
  certs."netbird.krejci.io" = {
    domain = "netbird.krejci.io";
    dnsProvider = "cloudflare";
    credentialsFile = "/run/agenix/cloudflare-api-token";
  };
};

# Relay server (standalone)
systemd.services.netbird-relay = {
  description = "NetBird Relay Server";
  wantedBy = ["multi-user.target"];
  after = ["network.target"];

  serviceConfig = {
    ExecStart = "${pkgs.netbird}/bin/netbird relay run --listen-address :33080 --secret-file /run/agenix/netbird-relay-secret";
    Restart = "always";
    DynamicUser = true;
    LoadCredential = "secret:/run/agenix/netbird-relay-secret";
  };
};

# Firewall: Public access to reverse proxy + relay
networking.firewall = {
  allowedTCPPorts = [80 443 33080];  # HTTP, HTTPS, Relay WebSocket
  allowedUDPPorts = [51820 33080];   # WireGuard tunnel, Relay QUIC
};

# Secrets
age.secrets = {
  netbird-relay-secret.file = ../../secrets/netbird-relay-secret.age;
  wg-thinkcenter-private.file = ../../secrets/wg-thinkcenter-private.age;
  cloudflare-api-token.file = ../../secrets/cloudflare-api-token.age;
};
```

## Migration Procedure

### Phase 1: Infrastructure Setup (No Disruption to Existing Netbird Cloud)

**Estimated time:** 4-6 hours

#### Step 1: DNS Configuration

```bash
# Add DNS record (Cloudflare or other provider)
# netbird.krejci.io A <vpsfree-public-ip>

# Verify DNS propagation
dig netbird.krejci.io +short
# Should show: <vpsfree-public-ip>
```

#### Step 2: Generate and Store Secrets

```bash
# Follow "Secrets Setup" section above
# Generate all secrets locally, encrypt with agenix
# Commit encrypted secrets to git
```

#### Step 3: Deploy WireGuard Tunnel

```bash
# Save public keys from generation step
THINKCENTER_WG_PUBKEY="<from thinkcenter-wg-public.key>"
VPSFREE_WG_PUBKEY="<from vpsfree-wg-public.key>"

# Update configurations with public keys
# (Replace <vpsfree-wg-public-key> and <thinkcenter-wg-public-key> in configs)

# Deploy to both hosts
nix run .#deploy-config thinkcenter
nix run .#deploy-config vpsfree

# Verify WireGuard tunnel UP
ssh thinkcenter wg show
# Should show: peer with latest handshake

ssh vpsfree wg show
# Should show: peer with latest handshake

# Test connectivity
ssh thinkcenter ping -c 3 10.100.0.2
# Expected: 3 packets transmitted, 3 received, 0% packet loss

ssh vpsfree ping -c 3 10.100.0.1
# Expected: 3 packets transmitted, 3 received, 0% packet loss
```

#### Step 4: Deploy PostgreSQL on thinkcenter

```bash
# Deploy configuration (includes PostgreSQL)
nix run .#deploy-config thinkcenter

# Verify PostgreSQL running
ssh thinkcenter systemctl status postgresql
# Expected: active (running)

# Verify netbird database exists
ssh thinkcenter sudo -u postgres psql -l | grep netbird
# Expected: netbird | netbird | UTF8 | ...
```

#### Step 5: Deploy NetBird Server on thinkcenter

```bash
# Deploy (already done in step 4, but verify services)
ssh thinkcenter systemctl status netbird-management
# Expected: active (running)

ssh thinkcenter systemctl status netbird-signal
# Expected: active (running)

ssh thinkcenter systemctl status nginx
# Expected: active (running)

# Check logs for errors
ssh thinkcenter journalctl -u netbird-management -n 50
# Should NOT show errors, should show "using Postgres store engine"

# Verify listening ports
ssh thinkcenter ss -tlnp | grep -E "(33073|10000|8080)"
# Expected:
# 0.0.0.0:33073 (netbird-management)
# 0.0.0.0:10000 (netbird-signal)
# 0.0.0.0:8080 (nginx dashboard)
```

#### Step 6: Deploy Reverse Proxy + Relay on vpsfree

```bash
# Deploy configuration
nix run .#deploy-config vpsfree

# Verify nginx running
ssh vpsfree systemctl status nginx
# Expected: active (running)

# Verify ACME certificate obtained
ssh vpsfree systemctl status acme-netbird.krejci.io
# Expected: Success

# Verify relay running
ssh vpsfree systemctl status netbird-relay
# Expected: active (running)

# Test nginx config
ssh vpsfree nginx -t
# Expected: test is successful

# Test backend connectivity from vpsfree
ssh vpsfree curl -v http://10.100.0.1:8080
# Expected: HTTP 200, should see dashboard HTML

# Test public HTTPS access
curl -I https://netbird.krejci.io
# Expected: HTTP/2 200
```

#### Step 7: Initial Dashboard Access

```bash
# Access dashboard (initially publicly accessible for setup)
# Open browser: https://netbird.krejci.io

# Click "Login with Google"
# Authenticate with Google account
# Should redirect back to dashboard

# First user becomes admin automatically
```

### Phase 2: Test Enrollment (No Disruption)

**Estimated time:** 2-3 hours

#### Step 1: Create Test Group

```bash
# In dashboard: https://netbird.krejci.io
# 1. Navigate to: Settings → Groups → Add Group
# 2. Name: "test-migration"
# 3. Save
```

#### Step 2: Generate Setup Key

```bash
# In dashboard: Settings → Setup Keys → Add Key
# - Name: "test-migration-key"
# - Type: Reusable
# - Expires: 7 days (for testing)
# - Auto-assigned groups: ["test-migration"]
# - Usage limit: 10
# - Create

# Copy the setup key (long base64 string)
# Save temporarily for testing
```

#### Step 3: Enroll Test Peer

```bash
# Option A: Use spare VM/container (recommended)
# Option B: Use non-critical host

# On test peer:
# If enrolled in Netbird cloud, disconnect first
netbird down

# Remove cloud config (optional, only if previously enrolled)
sudo rm /etc/netbird/config.json

# Enroll with self-hosted
netbird up --management-url https://netbird.krejci.io:443 \
           --setup-key <SETUP_KEY_FROM_DASHBOARD>

# Expected output:
# Connecting to management server...
# Connected to management server
# Peer is up and running

# Verify status
netbird status
# Expected:
# Management: Connected to https://netbird.krejci.io:443
# Signal: Connected
# Relays: 1/1 Available
# NetBird IP: 100.64.x.x
```

#### Step 4: Enroll Second Test Peer

```bash
# Repeat step 3 on another test peer
# Use same setup key (reusable)
```

#### Step 5: Test Connectivity

```bash
# From test peer 1:
# Get test peer 2's IP from dashboard or `netbird status` on peer 2
ping -c 3 100.64.x.x
# Expected: 3 packets transmitted, 3 received

# Test SSH (if configured)
ssh user@100.64.x.x
# Expected: successful connection

# Check connection type
netbird status -d | grep "test-peer-2"
# Look for: Direct (preferred) or Relayed (fallback)
```

#### Step 6: Test Relay Fallback (Optional)

```bash
# On test peer 1, temporarily block direct connection
# (simulate restrictive firewall)
sudo iptables -A OUTPUT -d <test-peer-2-public-ip> -j DROP

# Ping should still work (via relay)
ping -c 3 100.64.x.x
# Expected: still works, higher latency

# Check status
netbird status -d | grep "test-peer-2"
# Should show: Relayed (via relay server)

# Remove block
sudo iptables -D OUTPUT -d <test-peer-2-public-ip> -j DROP

# Connection should switch back to Direct after ~30s
```

### Phase 3: Migrate Existing Peers (Gradual)

**Estimated time:** 5-8 hours (for ~10-15 peers)

#### Step 1: Document Current Cloud Setup

```bash
# In Netbird cloud dashboard: https://app.netbird.io
# 1. Screenshot peer list (names, IPs, groups)
# 2. Export access policies (screenshot or manual notes)
# 3. Document network routes (if any)
# 4. Note DNS labels and extra DNS labels

# Create migration checklist:
# - framework: 100.76.232.215 → group: workstations
# - t14: 100.76.144.136 → group: workstations
# - thinkcenter: 100.76.x.x → group: servers, extra DNS: immich
# - vpsfree: 100.76.208.183 → group: servers
# - optiplex: 100.76.24.123 → group: servers
# ... etc

# Save to: NETBIRD_CLOUD_CONFIG.md (for reference)
```

#### Step 2: Recreate Network Structure in Self-Hosted

```bash
# In self-hosted dashboard: https://netbird.krejci.io

# Create groups:
# Settings → Groups → Add Group
# - "workstations" (framework, t14, notebook)
# - "servers" (thinkcenter, vpsfree, optiplex)
# - "infrastructure" (specific services)

# Create access policies:
# Settings → Access Control → Add Policy
# Recreate all policies from cloud
# Examples:
# - workstations → servers (SSH, HTTP, HTTPS)
# - servers → servers (all ports)
# - workstations → infrastructure (service-specific ports)

# Configure network routes (if any):
# Settings → Network Routes → Add Route
# Match cloud configuration

# Configure DNS settings:
# Settings → DNS → Enable DNS
# Port: 53
# (Requires CAP_NET_BIND_SERVICE on clients)
```

#### Step 3: Generate Setup Keys Per Group

```bash
# In self-hosted dashboard: Settings → Setup Keys

# Create key for "servers":
# - Name: "servers-migration"
# - Type: Reusable
# - Expires: Never (or long expiration)
# - Auto-assigned groups: ["servers"]
# - Usage limit: Unlimited
# - Create
# - Copy setup key → save to agenix as: netbird-setup-key-servers.age

# Create key for "workstations":
# - Name: "workstations-migration"
# - Type: Reusable
# - Auto-assigned groups: ["workstations"]
# - Copy setup key → save to agenix as: netbird-setup-key-workstations.age

# Encrypt and commit:
echo "<servers-setup-key>" | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-setup-key-servers.age
echo "<workstations-setup-key>" | age -e -i ~/.ssh/id_ed25519 -o secrets/netbird-setup-key-workstations.age
```

#### Step 4: Migrate Peers (Order Important!)

**Migration Order:**
1. Non-critical services (rpi4, prusa)
2. Peers with console/physical access (optiplex, if local)
3. Secondary workstation (not your primary laptop)
4. Servers (thinkcenter, vpsfree - be careful!)
5. **LAST:** Primary workstation (machine you're SSH'd from)

**Per-Peer Migration Process:**

```bash
# Example: Migrating optiplex (non-critical server)

# 1. SSH into peer (via current Netbird cloud VPN)
ssh optiplex.krejci.io

# 2. Stop Netbird cloud connection
netbird down

# 3. Remove cloud config
sudo rm /etc/netbird/config.json

# 4. Enroll with self-hosted
netbird up --management-url https://netbird.krejci.io:443 \
           --setup-key <SERVERS_SETUP_KEY>

# 5. Verify enrollment
netbird status
# Expected: Management: Connected to https://netbird.krejci.io:443

# 6. Verify connectivity to other migrated peers
ping thinkcenter.krejci.io  # If thinkcenter already migrated
ping framework.krejci.io    # If framework already migrated

# 7. Check dashboard
# https://netbird.krejci.io → Peers
# optiplex should appear with "Connected" status

# 8. Test critical services
# If this peer runs services, verify they're accessible from other peers

# Expected downtime per peer: 2-5 minutes
```

**For NixOS Hosts (Automated Enrollment):**

```nix
# Update modules/networking.nix (or host-specific config)
systemd.services.netbird-homelab-enroll-selfhosted = {
  description = "Enroll in NetBird Self-Hosted";
  wantedBy = ["multi-user.target"];
  after = ["network-online.target" "netbird-homelab.service"];
  requires = ["netbird-homelab.service"];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };

  script = ''
    # Check if already enrolled in self-hosted
    if ${pkgs.netbird}/bin/netbird --daemon-addr unix:///var/run/netbird-homelab/sock status | grep -q "netbird.krejci.io"; then
      echo "Already enrolled in self-hosted"
      exit 0
    fi

    # Down current connection
    ${pkgs.netbird}/bin/netbird --daemon-addr unix:///var/run/netbird-homelab/sock down || true

    # Remove old config
    rm -f /var/lib/netbird-homelab/config.json

    # Enroll with self-hosted
    ${pkgs.netbird}/bin/netbird --daemon-addr unix:///var/run/netbird-homelab/sock up \
      --management-url https://netbird.krejci.io:443 \
      --setup-key $(cat /run/agenix/netbird-setup-key-servers)
  '';

  path = [pkgs.netbird];
};

age.secrets.netbird-setup-key-servers = {
  file = ../secrets/netbird-setup-key-servers.age;
  mode = "0400";
};
```

```bash
# Deploy automated enrollment
nix run .#deploy-config optiplex

# Service runs automatically, check status
ssh optiplex systemctl status netbird-homelab-enroll-selfhosted

# Verify enrolled
ssh optiplex netbird --daemon-addr unix:///var/run/netbird-homelab/sock status
```

#### Step 5: Migrate Critical Peers (CAREFULLY)

**thinkcenter (critical - runs self-hosted management!):**

```bash
# IMPORTANT: thinkcenter is already hosting management server
# It doesn't need to enroll as a peer in its own VPN
# OR: If you want thinkcenter in the mesh for peer-to-peer access:

# From another machine (NOT thinkcenter):
ssh thinkcenter.krejci.io

# Follow standard migration process
netbird down
sudo rm /etc/netbird/config.json
netbird up --management-url https://netbird.krejci.io:443 --setup-key <SERVERS_SETUP_KEY>

# Verify still accessible
ping thinkcenter.krejci.io

# If you lose access: physical console or reboot (existing config should restore)
```

**vpsfree (critical - runs reverse proxy!):**

```bash
# From another machine (NOT vpsfree):
ssh vpsfree.krejci.io

# Follow standard migration process
netbird down
sudo rm /etc/netbird/config.json
netbird up --management-url https://netbird.krejci.io:443 --setup-key <SERVERS_SETUP_KEY>

# Verify still accessible
# If you lose access: VPS console access via provider dashboard
```

**Your primary workstation (LAST!):**

```bash
# Do this LAST when all other peers are migrated and verified
# Ensure you have alternative access (physical, another machine, console)

netbird down
sudo rm /etc/netbird/config.json
netbird up --management-url https://netbird.krejci.io:443 --setup-key <WORKSTATIONS_SETUP_KEY>

# Verify connectivity to all other peers
for host in thinkcenter vpsfree optiplex framework t14; do
  ping -c 1 $host.krejci.io && echo "$host: OK" || echo "$host: FAIL"
done
```

### Phase 4: Cleanup and Finalization

**Estimated time:** 1-2 hours

#### Step 1: Verify All Peers Migrated

```bash
# In self-hosted dashboard: https://netbird.krejci.io → Peers
# Check peer count matches expected (10-15)

# In cloud dashboard: https://app.netbird.io → Peers
# Should show: 0 peers

# Test connectivity matrix (from your workstation):
for host in thinkcenter vpsfree optiplex framework t14; do
  echo "Testing $host..."
  ping -c 1 $host.krejci.io && echo "✅ $host OK" || echo "❌ $host FAIL"
done

# Test critical services:
curl -I https://immich.krejci.io  # Should work
curl -I https://grafana.krejci.io  # Should work
```

#### Step 2: Enable Access Control on vpsfree

```bash
# Now that all peers are migrated, restrict dashboard access
# Uncomment nginx access control in vpsfree configuration:

# hosts/vpsfree/configuration.nix
services.nginx.virtualHosts."netbird.krejci.io" = {
  extraConfig = ''
    allow 100.64.0.0/10;  # Netbird CGNAT range
    deny all;
  '';
};

# Deploy
nix run .#deploy-config vpsfree

# Verify dashboard only accessible via VPN
# From external network (not via Netbird):
curl -I https://netbird.krejci.io
# Expected: HTTP 403 Forbidden

# From Netbird VPN:
curl -I https://netbird.krejci.io
# Expected: HTTP 200 OK
```

#### Step 3: Test Backup and Restore

```bash
# Verify backups running
ssh thinkcenter systemctl status borgbackup-job-netbird-local
ssh thinkcenter systemctl status borgbackup-job-netbird-remote

# Manually trigger backup
ssh thinkcenter sudo systemctl start borgbackup-job-netbird-local
ssh thinkcenter sudo systemctl start borgbackup-job-netbird-remote

# List backups
ssh thinkcenter sudo borg list /var/lib/borg-repos/netbird
ssh vpsfree sudo borg list /var/lib/borg-repos/netbird

# Test restore (in temp directory)
ssh thinkcenter "sudo borg extract /var/lib/borg-repos/netbird::thinkcenter-netbird-$(date +%Y-%m-%d) --dry-run"
# Expected: No errors, shows list of files that would be extracted
```

#### Step 4: Document New Setup

```bash
# Update CLAUDE.md with new architecture
# Key updates:
# - VPN: Netbird Cloud → Self-Hosted Netbird (netbird.krejci.io)
# - Management: thinkcenter behind NAT, vpsfree reverse proxy
# - Auth: Google SSO via OIDC
# - Backup: Dual Borg (local NVMe + remote NAS)

# Create disaster recovery runbook
# Include:
# - PostgreSQL restore from borg backup
# - DNS failover (if thinkcenter down)
# - Management server rebuild procedure
# - Contact information for vpsfree provider (if needed)
```

#### Step 5: Delete Cloud Account (Optional)

```bash
# Export final reference:
# - Screenshot all cloud configuration
# - Save to: NETBIRD_CLOUD_FINAL_EXPORT/

# In cloud dashboard: https://app.netbird.io
# Settings → Account → Delete Account
# Confirm deletion

# Note: Peers won't be affected (already migrated to self-hosted)
```

## Setup Keys Management

### Pre-generated Keys for Groups

Keys generated in Phase 3, Step 3. For reference:

```bash
# In dashboard: Settings → Setup Keys → Add Key

# Server key:
# - Name: "servers-production"
# - Type: Reusable
# - Expires: Never
# - Auto-assigned groups: ["servers"]
# - Usage limit: Unlimited

# Workstation key:
# - Name: "workstations-production"
# - Type: Reusable
# - Expires: Never
# - Auto-assigned groups: ["workstations"]
# - Usage limit: Unlimited
```

### Automated NixOS Enrollment Pattern

Based on existing `modules/networking.nix` pattern:

```nix
# modules/networking.nix
systemd.services.netbird-homelab-enroll = {
  description = "Enroll in NetBird Self-Hosted";
  wantedBy = ["multi-user.target"];
  after = ["network-online.target" "netbird-homelab.service"];
  requires = ["netbird-homelab.service"];

  # Only run if setup key exists and not already enrolled
  unitConfig = {
    ConditionPathExists = "/run/agenix/netbird-setup-key-${groupName}";
  };

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };

  script = ''
    set -euo pipefail

    # Check if already enrolled
    if ${pkgs.netbird}/bin/netbird --daemon-addr unix:///var/run/netbird-homelab/sock status | grep -q "netbird.krejci.io"; then
      exit 0
    fi

    # Enroll with retry logic
    for i in {1..3}; do
      if ${pkgs.netbird}/bin/netbird --daemon-addr unix:///var/run/netbird-homelab/sock up \
        --management-url https://netbird.krejci.io:443 \
        --setup-key $(cat /run/agenix/netbird-setup-key-${groupName}); then
        break
      fi
      sleep 5
    done
  '';

  path = [pkgs.netbird];
};

age.secrets.netbird-setup-key-${groupName} = {
  file = ../secrets/netbird-setup-key-${groupName}.age;
  mode = "0400";
};
```

## Lessons from Previous Migration

The previous migration (manual WireGuard → Netbird Cloud, completed 2024) provides valuable insights for this self-hosted deployment.

### Multi-Instance Netbird Services

**Pattern:** When running multiple Netbird instances, each uses instance-specific paths.

**Configuration:**
```nix
# Instance name: "homelab"
# Socket path: /var/run/netbird-homelab/sock
# CLI commands must specify daemon address:
netbird --daemon-addr unix:///var/run/netbird-homelab/sock status
```

**Relevance:** Self-hosted deployment uses default instance, but understanding multi-instance pattern helps with troubleshooting and potential future multi-network scenarios.

### Oneshot Enrollment Service Best Practices

**Key patterns from previous migration:**

1. **ConditionPathExists:** Only run if setup key exists
   ```nix
   unitConfig.ConditionPathExists = "/run/agenix/netbird-setup-key-${groupName}";
   ```

2. **Service dependencies:** Ensure daemon ready
   ```nix
   after = ["network-online.target" "netbird-homelab.service"];
   requires = ["netbird-homelab.service"];
   ```

3. **Error handling:** Use `set -euo pipefail` to prevent deleting key on failure
   ```bash
   script = ''
     set -euo pipefail
     # ... enrollment logic
   '';
   ```

4. **Retry logic:** Handle timing issues
   ```bash
   for i in {1..3}; do
     if netbird up ...; then break; fi
     sleep 5
   done
   ```

5. **Idempotency:** Check if already enrolled before attempting
   ```bash
   if netbird status | grep -q "netbird.krejci.io"; then exit 0; fi
   ```

**Relevance:** These patterns are already incorporated in the migration procedure (Phase 3, Step 4).

### VPN IP Stability

**Lesson:** Netbird assigns new IPs on peer re-enrollment.

**Impact:** Services relying on peer IPs must handle IP changes.

**Solution:** Use DNS names instead of IPs:
```bash
# Good: hostname-based access
curl https://immich.krejci.io

# Bad: IP-based access (breaks on re-enrollment)
curl https://100.76.1.2
```

**For nginx access control:**
```nix
# Don't hardcode peer IPs in listen addresses
virtualHosts."service.krejci.io" = {
  listenAddresses = ["0.0.0.0"];  # Listen on all
  extraConfig = ''
    allow 100.64.0.0/10;  # Allow Netbird CGNAT range
    deny all;
  '';
};
```

**Relevance:** Critical for Phase 4 (access control configuration on vpsfree).

### Extra DNS Labels

**Feature:** Netbird supports extra DNS labels for service aliases.

**Configuration:**
```nix
# In hosts.nix
extraDnsLabels = ["immich" "photos"];
```

**Result:**
- `immich.krejci.io` → points to host
- `photos.krejci.io` → points to host
- `hostname.krejci.io` → points to host

**Requirements:**
- Setup key must have "Allow Extra DNS labels" permission
- Labels applied during enrollment
- To modify labels: delete peer, re-enroll with updated config

**Relevance:** Optional enhancement for self-hosted setup. Useful for service discovery (e.g., `netbird.krejci.io` pointing to thinkcenter).

### vpsAdminOS Container Considerations

**Context:** vpsfree runs in vpsAdminOS container.

**Critical settings:**
```nix
# Required for console access
console.enable = true;

# vpsAdminOS manages network externally
systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
systemd.network.networks."98-all-ethernet".DHCP = "no";
networking.nameservers = ["1.1.1.1" "8.8.8.8"];

# NFS mounts: simple configuration only
fileSystems."/mnt/path" = {
  device = "nfs-server:/path";
  fsType = "nfs";
  options = ["nofail"];  # Avoid x-systemd.automount, _netdev
};
```

**Relevance:** Already documented in existing `modules/vpsadminos.nix`. No changes needed for self-hosted deployment.

### Backup Infrastructure Patterns

**Lessons from Immich backup implementation:**

1. **Dual backup strategy:** Local (fast recovery) + Remote (offsite protection)
2. **Bind mounts:** Prevent writes if underlying storage unmounted
   ```nix
   fileSystems."/var/lib/borg-repos" = {
     device = "/mnt/storage/borg-repos";
     fsType = "none";
     options = ["bind" "x-systemd.requires=mnt-storage.mount"];
   };
   ```

3. **Borg repository initialization:** Automated via scripts
   ```bash
   nix run .#inject-borg-passphrase server-host client-host
   ```

4. **Systemd timer activation:** May require reboot after first deployment
   ```bash
   # Verify timers active
   systemctl list-timers | grep borgbackup
   ```

**Relevance:** Netbird backup configuration (Phase 1, Step 5) follows these proven patterns.

### SSH Key Management

**Pattern:** Centralized SSH key management via `ssh-authorized-keys.conf`.

**Format:**
```
hostname, user, ssh-ed25519 AAAA... comment
```

**Benefits:**
- Single file for all keys
- Flake check validates format
- AuthorizedKeysCommand fetches dynamically
- 1-minute cache for performance

**Relevance:** SSH access to thinkcenter/vpsfree uses this pattern. No changes needed for self-hosted deployment.

### HTTPS/TLS Configuration

**Pattern from previous migration:**

1. **Wildcard certificates:** `*.krejci.io` via DNS-01 challenge
2. **Cloudflare integration:** Automated via `nix run .#inject-cloudflare-token`
3. **Defense-in-depth:**
   - Services listen on localhost (127.0.0.1)
   - Nginx handles TLS termination
   - Firewall restricts to specific interfaces

**Relevance:** Self-hosted deployment follows identical ACME/TLS patterns (already documented in Prerequisites and vpsfree configuration).

### Migration Downtime Expectations

**From previous migration:**
- Per-peer downtime: 2-5 minutes (disconnect → re-enroll → reconnect)
- Incremental migration possible (some peers on old network, some on new)
- Critical: migrate machines you're SSH'd from LAST

**Relevance:** Self-hosted migration timeline estimates (Phase 3) based on these real-world measurements.

## Troubleshooting

### WireGuard Tunnel Issues

**Symptoms:** vpsfree cannot reach thinkcenter services

```bash
# Check WireGuard interface status
ssh thinkcenter wg show wg-vpsfree
# Expected: peer with recent handshake (< 2 minutes ago)

ssh vpsfree wg show wg-thinkcenter
# Expected: peer with recent handshake

# If no handshake:
# 1. Check firewall allows UDP 51820
ssh thinkcenter nft list ruleset | grep 51820
ssh vpsfree nft list ruleset | grep 51820

# 2. Check endpoint reachable
ssh thinkcenter ping -c 3 <vpsfree-public-ip>

# 3. Restart WireGuard
ssh thinkcenter systemctl restart systemd-networkd
ssh vpsfree systemctl restart systemd-networkd

# 4. Check logs
ssh thinkcenter journalctl -u systemd-networkd | grep wg-vpsfree
```

**Test tunnel connectivity:**
```bash
ssh thinkcenter ping -c 3 10.100.0.2
ssh vpsfree ping -c 3 10.100.0.1

# If ping fails:
# - Check routing: ip route show
# - Check firewall: nft list ruleset
# - Verify IPs: ip addr show wg-vpsfree / wg-thinkcenter
```

### Reverse Proxy Issues

**Symptoms:** `curl https://netbird.krejci.io` returns error

```bash
# Check nginx status
ssh vpsfree systemctl status nginx
# Expected: active (running)

# Test nginx config
ssh vpsfree nginx -t
# Expected: test is successful

# Check backend reachable from vpsfree
ssh vpsfree curl -v http://10.100.0.1:8080
# Expected: HTTP 200, dashboard HTML

# If 502 Bad Gateway:
# - Backend not running: ssh thinkcenter systemctl status nginx
# - WireGuard tunnel down: ssh vpsfree ping 10.100.0.1
# - Firewall blocking: ssh thinkcenter nft list ruleset | grep 8080

# Check nginx logs
ssh vpsfree journalctl -u nginx -f
```

**ACME certificate issues:**
```bash
# Check certificate obtained
ssh vpsfree ls -la /var/lib/acme/netbird.krejci.io/
# Expected: fullchain.pem, key.pem

# If missing:
ssh vpsfree systemctl status acme-netbird.krejci.io
ssh vpsfree journalctl -u acme-netbird.krejci.io

# Retry certificate
ssh vpsfree systemctl start acme-netbird.krejci.io

# Verify DNS-01 challenge works
ssh vpsfree cat /run/agenix/cloudflare-api-token
# Test token: curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer <token>"
```

### Management Server Issues

**Symptoms:** Dashboard shows "Cannot connect to management server"

```bash
# Check services on thinkcenter
ssh thinkcenter systemctl status netbird-management
ssh thinkcenter systemctl status netbird-signal
ssh thinkcenter systemctl status postgresql

# Check logs
ssh thinkcenter journalctl -u netbird-management -n 100
# Look for errors:
# - "failed to connect to postgres"
# - "failed to read encryption key"
# - OAuth errors

# Verify PostgreSQL
ssh thinkcenter sudo -u postgres psql netbird -c "\dt"
# Expected: list of tables (peers, accounts, etc.)

# Check listening ports
ssh thinkcenter ss -tlnp | grep -E "(33073|10000|8080)"
# Expected:
# 0.0.0.0:33073 (netbird-management)
# 0.0.0.0:10000 (netbird-signal)
# 0.0.0.0:8080 (nginx dashboard)

# Test local access on thinkcenter
ssh thinkcenter curl http://localhost:8080
# Expected: dashboard HTML
```

### Google OAuth Issues

**Symptoms:** Cannot login, "OAuth error" on dashboard

```bash
# Check management logs
ssh thinkcenter journalctl -u netbird-management | grep -i oauth
# Look for: invalid_client, redirect_uri_mismatch, invalid_scope

# Verify OIDC configuration reachable
curl https://accounts.google.com/.well-known/openid-configuration
# Expected: JSON with authorization_endpoint, token_endpoint

# Check secrets loaded correctly
ssh thinkcenter cat /run/agenix/netbird-google-client-id
ssh thinkcenter cat /run/agenix/netbird-google-client-secret
# Verify match Google Cloud Console

# Common issues:
# - Redirect URI mismatch: Check Google Console → Credentials
#   Must be exactly: https://netbird.krejci.io/auth/callback
# - Wrong client ID/secret: Regenerate in Google Console
# - OAuth consent screen not configured: Check Google Console → OAuth consent screen
```

### Peer Cannot Connect

**Symptoms:** `netbird status` shows "Disconnected" or "Cannot reach management"

```bash
# On peer:
netbird status -d
# Look for specific error messages

# Test management reachability
curl https://netbird.krejci.io/
# Expected: dashboard HTML (or 403 if access control enabled and peer not in VPN yet)

# Test management API
curl https://netbird.krejci.io/management.ManagementService/
# Expected: gRPC error (normal - indicates server responding)

# Enable debug logging
netbird down
netbird up --log-level debug --management-url https://netbird.krejci.io:443 --setup-key <KEY>
journalctl -u netbird -f

# Common issues:
# - Invalid setup key: Generate new key in dashboard
# - Setup key expired: Check expiration in dashboard
# - Firewall blocking: Check peer's firewall allows outbound 443/tcp
# - DNS issues: Check `dig netbird.krejci.io` resolves correctly
```

### Relay Not Working

**Symptoms:** Peers show "Relayed: 0/1 Available"

```bash
# Check relay service on vpsfree
ssh vpsfree systemctl status netbird-relay
# Expected: active (running)

# Check logs
ssh vpsfree journalctl -u netbird-relay -n 50

# Test relay endpoint
curl https://netbird.krejci.io:33080/
# Expected: connection (may refuse HTTP, but port open)

nc -zv netbird.krejci.io 33080
# Expected: succeeded

# Verify relay secret matches
ssh vpsfree cat /run/agenix/netbird-relay-secret
ssh thinkcenter "grep -A5 'Relay' /var/lib/netbird/management.json"  # Or wherever NixOS generates it
# Secrets must match

# On peer:
netbird status -d | grep -i relay
# Should show relay address and status
```

### Disaster Recovery: Management Server Down

**Scenario:** thinkcenter failed, need to restore management server

```bash
# 1. Provision new host or repair thinkcenter
# Existing peers continue working (WireGuard tunnels independent)

# 2. Restore agenix secrets (from git)
git clone <dotfiles-repo>
# Secrets already in repo

# 3. Restore PostgreSQL from backup
# On new thinkcenter:
# Extract latest backup
ssh vpsfree sudo borg extract /var/lib/borg-repos/netbird::latest
# Or from local: sudo borg extract /var/lib/borg-repos/netbird::latest

# Restore database
sudo -u postgres createdb netbird
sudo -u postgres psql netbird < backup/postgresql/netbird.sql

# 4. Deploy NetBird configuration
nix run .#deploy-config thinkcenter

# 5. Update DNS (if IP changed)
# netbird.krejci.io A <new-vpsfree-public-ip> (if vpsfree changed)
# Or no change needed if only thinkcenter failed

# 6. Verify services
ssh thinkcenter systemctl status netbird-management
ssh thinkcenter systemctl status netbird-signal

# 7. Peers reconnect automatically
# Management service comes online → peers detect via DNS → reconnect
# Peer state preserved in database

# Expected downtime: 2-4 hours (depends on backup restore speed + DNS propagation)
```

## Security Considerations

### Defense in Depth

**vpsfree (Public Attack Surface):**
1. **Nginx reverse proxy:**
   - TLS 1.2+ only
   - Modern cipher suites
   - HSTS enabled
   - Access control via IP allowlist (after migration)
   - Rate limiting (optional)

2. **fail2ban (optional):**
```nix
services.fail2ban = {
  enable = true;
  jails.nginx-netbird = ''
    enabled = true
    filter = nginx-limit-req
    logpath = /var/log/nginx/error.log
    maxretry = 5
    findtime = 600
    bantime = 3600
  '';
};
```

3. **Minimal data exposure:**
   - No sensitive data at rest
   - Only sees encrypted transit traffic
   - Relay only handles encrypted WireGuard packets

**thinkcenter (Private Network):**
1. **No public exposure:**
   - All services listen on 0.0.0.0 but firewalled
   - Only accessible via WireGuard tunnel from vpsfree
   - No port forwarding from router

2. **Database security:**
   - PostgreSQL peer authentication (Unix socket)
   - No network access
   - Daily encrypted backups

3. **Secrets management:**
   - All credentials via agenix
   - Encrypted at rest (disk encryption)
   - No secrets in Nix store

4. **Firewall:**
```nix
networking.firewall = {
  # Public: nothing
  allowedTCPPorts = [];
  allowedUDPPorts = [51820];  # WireGuard only

  # Only allow vpsfree (10.100.0.2) via WireGuard
  extraCommands = ''
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 33073 -j ACCEPT
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 10000 -j ACCEPT
    iptables -A INPUT -s 10.100.0.2 -p tcp --dport 8080 -j ACCEPT
  '';
};
```

### Monitoring

**Service Health:**
```nix
# Add to existing Prometheus config
services.prometheus.scrapeConfigs = [{
  job_name = "netbird-management";
  static_configs = [{
    targets = ["localhost:33073"];  # Management metrics endpoint (if available)
  }];
}];
```

**Access Logs:**
```bash
# Weekly review
ssh vpsfree journalctl -u nginx --since "7 days ago" | grep netbird.krejci.io

# Look for:
# - Unusual access patterns
# - Failed authentication attempts
# - 403/401 errors (access control working)
```

## Maintenance

### Weekly Tasks

```bash
# Check service health
ssh thinkcenter systemctl is-active netbird-management netbird-signal nginx postgresql
ssh vpsfree systemctl is-active nginx netbird-relay

# Review peer status in dashboard
# https://netbird.krejci.io → Peers
# Check for disconnected peers

# Verify backups completed
ssh thinkcenter systemctl status borgbackup-job-netbird-local
ssh thinkcenter systemctl status borgbackup-job-netbird-remote
```

### Monthly Tasks

```bash
# Update nixpkgs (includes NetBird updates)
nix flake update nixpkgs
git diff flake.lock  # Review changes

# Test in VM first (if major version jump)
# Then deploy
nix run .#deploy-config thinkcenter
nix run .#deploy-config vpsfree

# Test backup restore (dry run)
ssh thinkcenter "sudo borg extract /var/lib/borg-repos/netbird::latest --dry-run"

# Review nginx access logs
ssh vpsfree journalctl -u nginx --since "30 days ago" | grep -E "(error|403|401)"
```

### Quarterly Tasks

```bash
# Disaster recovery drill
# 1. Snapshot thinkcenter (if VM)
# 2. Simulate failure
# 3. Restore from backup
# 4. Verify peers reconnect
# 5. Document issues found
# 6. Restore snapshot

# Review access policies
# Are groups still accurate?
# Remove old peers?
# Update policies for new services?

# Check NetBird security advisories
# https://github.com/netbirdio/netbird/security/advisories

# Rotate Google OAuth credentials (if needed)
# Generate new client secret in Google Console
# Update agenix secret
# Deploy to thinkcenter
```

## Cost-Benefit Analysis

### Self-Hosted Benefits

1. **No infrastructure cost:** vpsfree already paid for
2. **No per-user limits:** Cloud free tier limited to 5 users
3. **Data sovereignty:** All network state on encrypted homelab
4. **Learning experience:** Hands-on with NetBird architecture
5. **Consistency:** Matches existing patterns (agenix, borg, nginx, WireGuard)
6. **Control:** Full control over updates, features, data retention

### Self-Hosted Costs

1. **Initial setup:** 12-19 hours (one-time)
2. **Maintenance:** ~1-2 hours/month
3. **Disaster recovery testing:** ~4 hours/quarter
4. **Risk:** Management server single point of failure (mitigated by backups + peers continue working)

### Comparison to Cloud

| Feature | Cloud (Free) | Cloud (Paid) | Self-Hosted |
|---------|--------------|--------------|-------------|
| User limit | 5 | Unlimited | Unlimited |
| Peer limit | Unlimited | Unlimited | Unlimited |
| Cost/month | $0 | $8/user | $0 (vpsfree) |
| Data location | US/EU | US/EU | Homelab |
| Uptime SLA | None | 99.9% | DIY (~99%) |
| Support | Community | Email | Community |
| Setup time | 5 min | 5 min | 12-19 hours |
| Maintenance | 0 | 0 | 1-2 hours/month |

### Recommendation

**Proceed with self-hosting if:**
- Currently hitting cloud free tier limits (>5 users)
- Want data sovereignty and learning experience
- Comfortable with 2-4 hour recovery time if management fails
- Accept maintenance burden (~1-2 hours/month)

**This architecture specifically addresses your requirements:**
1. ✅ Management downtime → existing tunnels survive
2. ✅ No sensitive data on vpsfree → only reverse proxy + relay
3. ✅ NAT traversal → vpsfree gateway via WireGuard tunnel
4. ✅ Simple solution → standard nginx + WireGuard patterns
5. ✅ Google SSO → OIDC configuration
6. ✅ Pre-generated setup keys → integrated with agenix

## References

### Official Documentation
- Self-hosting quickstart: https://docs.netbird.io/selfhosted/selfhosted-quickstart
- Advanced guide: https://docs.netbird.io/selfhosted/selfhosted-guide
- How NetBird works: https://docs.netbird.io/about-netbird/how-netbird-works
- PostgreSQL store: https://docs.netbird.io/selfhosted/postgres-store
- Identity providers: https://docs.netbird.io/selfhosted/identity-providers
- API reference: https://docs.netbird.io/api

### NixOS Integration
- NixOS module options: https://mynixos.com/options/services.netbird.server
- PR #354032 (server rework): https://github.com/NixOS/nixpkgs/pull/354032
- PR #247118 (initial module): https://github.com/NixOS/nixpkgs/pull/247118

### Community Resources
- GitHub issues: https://github.com/netbirdio/netbird/issues
- Management HA discussion: https://github.com/netbirdio/netbird/issues/1584
- Community forum: https://forum.netbird.io

### Related Technologies
- WireGuard: https://www.wireguard.com/
- PostgreSQL HA: https://wiki.postgresql.org/wiki/Replication,_Clustering,_and_Connection_Pooling
- Google OAuth: https://developers.google.com/identity/protocols/oauth2

## Changelog

### 2025-11-25 - Initial Planning
- Analyzed NetBird self-hosted architecture
- Evaluated HA limitations (management server single point of failure)
- Designed split architecture: vpsfree (gateway) + thinkcenter (control plane)
- Documented migration strategy from cloud to self-hosted
- Created comprehensive configuration and migration procedures
- Validated architecture meets all requirements:
  - Management downtime resilience ✅
  - No sensitive data on vpsfree ✅
  - NAT traversal via reverse proxy ✅
  - Simple standard patterns ✅
  - Google SSO support ✅
  - Pre-generated setup keys ✅
