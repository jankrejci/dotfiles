# Print Server - GNOME GUI Discovery

## CONSTRAINTS - READ 10 TIMES BEFORE DOING ANYTHING

pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications
pure default GNOME gui must work without modifications

server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients
server itself must ensure the proper information is distributed to clients

NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation
NEVER fabricate assumptions - verify with logs or documentation

NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM
NEVER offer "live with it" or "accept limitations" - SOLVE THE PROBLEM

---

## Final State (Success Criteria)

1. Open GNOME Settings → Printers
2. Click "Add Printer"
3. Enter `brother.krejci.io`
4. Printer is found and shown
5. Click Add
6. Printing works

Same for Android - enter hostname, printer found, printing works.

---

## What Works (Confirmed)

1. **GNOME with CUPS on VPN IP** - CUPS listening directly on 192.168.91.5:631 works
   - Enter `brother.krejci.io` in GNOME → printer found → printing works
   - `lpstat -h brother.krejci.io -p` shows the printer

2. **ipp-usb** exposes printer on localhost:60000 with IPP Everywhere paths

3. **Android first print** - Adding printer via full URI in Firefox works once
   - URI: `ipp://brother.krejci.io:631/printers/Brother-DCP-T730DW`
   - First print succeeds, then shows "unavailable"

4. **Scanning works** with explicit URL: `escl:http://brother.krejci.io:631`

5. **DNS resolution** works: `brother.krejci.io` resolves to `192.168.91.5` via Netbird

---

## What Doesn't Work

1. **Android entering just hostname** - Shows "printer not found"
   - Android tries `/ipp/printer`, `/ipp/print`, `/ipp` paths
   - CUPS serves at `/printers/Brother-DCP-T730DW`
   - All standard IPP paths return "printer does not exist"

2. **Android after first print** - Shows "unavailable", can't print again
   - Server logs show all responses are successful (200 OK)
   - Android caches "unavailable" state without making new requests
   - Only option is "Forget printer"

3. **mDNS over VPN** - Netbird is Layer 3, doesn't support multicast
   - Android needs mDNS to maintain printer availability status
   - Without mDNS refresh, Android marks printer unavailable after use

---

## Root Cause Analysis

### Why Android can't find printer by hostname:

1. **Path mismatch** - Android Default Print Service queries IPP Everywhere standard paths:
   - `/ipp/printer`
   - `/ipp/print`
   - `/ipp`

   But CUPS serves printers at `/printers/<name>`. These paths return 404.

2. **IPP protocol embeds URI in request body** - The `printer-uri` attribute is in the IPP request body, not just the HTTP path. nginx path rewriting doesn't help because CUPS reads the URI from the IPP body.

   Evidence from tcpdump:
   ```
   printer-uri.7ipp://brother.krejci.io:631/ipp/printer
   ```
   CUPS log:
   ```
   Get-Printer-Attributes (ipp://brother.krejci.io:631/ipp/printer) - not found
   ```

### Why Android shows "unavailable" after first print:

1. **mDNS required for availability refresh** - Android uses mDNS to track printer availability. Without mDNS broadcasts, Android caches the last known state.

2. **VPN doesn't support multicast** - Netbird is Layer 3 WireGuard-based, no multicast/broadcast support.

3. **HP Support confirms this is known behavior** - "When adding printer via Android Default Print Services, user can only print once; after that, printer is no longer available."

### Why GNOME works:

GNOME queries CUPS server directly at `ipp://hostname:631/` and gets the printer list. CUPS responds with available queues. No mDNS needed for initial discovery when hostname is entered manually.

---

## Previous Mistakes (Don't Repeat)

1. Client-side Avahi static services - User rejected, server-side only
2. system-config-printer - User rejected, GNOME GUI only
3. lpadmin commands - User rejected, no CLI for users
4. Preconfigured printer queues on client - User rejected
5. cups-browsed - Creates broken "Unknown" queues from _printer._tcp
6. Custom Avahi XML without CUPS - GNOME queries CUPS, not raw IPP
7. Mopria Print Service - User not interested, focus on Default Print Service
8. nginx path rewriting for IPP - FAILS because IPP embeds URI in request body
9. nginx with CUPS on localhost - Broke GNOME (which was working before)
10. Raw ipp-usb without CUPS - GNOME GUI can't discover it
11. nginx proxy to CUPS Unix socket - CUPS returns `printer-uri: ipp://localhost/...` in responses regardless of ServerName directive. Clients then try to connect to localhost on their own machine. Same issue with ipp-usb - it also returns localhost URIs.
12. nginx proxy to ipp-usb - Android can add printer successfully via /ipp/print path, but then shows "unavailable". tcpdump confirms ipp-usb returns `printer-uri-supported: ipp://localhost:60000/ipp/print` in response. Android stores this URI and uses it for subsequent status checks, which fail because localhost on Android doesn't have the printer. No ipp-usb config to override this.
13. ipp-usb with interface=all on port 60000 - When accessed directly on VPN IP:60000, ipp-usb returns correct `printer-uri-supported: ipp://brother.krejci.io:60000/ipp/print`. But Android Default Print Service ignores custom ports and always connects to port 631. tcpdump confirms `Host: brother.krejci.io:631` even when user enters `brother.krejci.io:60000`.

## Key Finding: ipp-usb Direct Access Works

When ipp-usb listens on all interfaces and is accessed directly (not proxied):
- `printer-uri-supported` returns the correct external URI
- Android can add and use the printer

The problem is Android always uses port 631. Solution: ipp-usb on port 631 directly.

---

## Technical Findings from Debugging

### tcpdump capture - Android adding printer by hostname:
```
POST /ipp/printer HTTP/1.1
Host: brother.krejci.io:631
User-Agent: CUPS/2.2.9 (Linux ... aarch64) IPP/2.0

printer-uri = ipp://brother.krejci.io:631/ipp/printer
requested-attributes = ipp-versions-supported, printer-make-and-model, ...
```

Response:
```
HTTP/1.1 200 OK
status-message = "The printer or class does not exist."
```

### tcpdump capture - Android successful print (via full URI):
```
POST /printers/Brother-DCP-T730DW HTTP/1.1
printer-uri = ipp://brother.krejci.io:631/printers/Brother-DCP-T730DW
```

All job states successful:
- `job-state-reasons: job-printing`
- `printer-state-reasons: cups-waiting-for-job-completed`
- `job-state: 9 (completed)`
- `job-state-reasons: job-completed-successfully`

After successful print, Android closes connection. Next print attempt shows "unavailable" without making any network request.

### Key insight:
The IPP protocol includes `printer-uri` in the **request body**, not just the HTTP path. CUPS uses the body URI to look up the printer. nginx HTTP path rewriting cannot fix this.

---

## Potential Solutions to Explore

### Option 1: CUPS printer alias/symlink
- Research if CUPS supports aliasing `/ipp/printer` to `/printers/<name>`
- Check if creating a printer named literally "ipp" with subpath "printer" works

### Option 2: IPP body rewriting proxy
- Use nginx with Lua module to parse and rewrite IPP request body
- Complex, error-prone, may break IPP protocol

### Option 3: ipp-usb with CUPS passthrough
- ipp-usb serves IPP Everywhere paths natively at /ipp/print
- Could we have both ipp-usb (for Android) and CUPS (for GNOME)?
- Different ports? Different IPs?

### Option 4: DNS-SD over unicast DNS
- Advertise printer via DNS TXT/SRV records instead of mDNS
- Android might support DNS-SD discovery
- Requires investigation

### Option 5: Accept Android "unavailable" limitation
- REJECTED per constraints - must solve the problem

---

## Current Working State (GNOME)

CUPS on VPN IP directly works for GNOME:

### Architecture:
```
[Client GNOME]
    → queries ipp://brother.krejci.io:631/
    → CUPS on server responds with queue list
    → GNOME shows "Brother DCP-T730DW"
    → User clicks Add
    → Printing goes through CUPS → ipp-usb → USB printer
```

---

## Implementation Code

### `homelab/print-server.nix`

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.print-server;
  global = config.homelab.global;
  printerDomain = "${cfg.subdomain}.${global.domain}";
  vpnInterface = "nb0";
  printerName = "Brother-DCP-T730DW";
  # ipp-usb on localhost, CUPS as frontend on VPN IP
  ippUsbPort = 60000;
in {
  options.homelab.print-server = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IPP-over-USB print server";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "VPN IP address for the print server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "brother";
      description = "Subdomain for print server";
    };
  };

  config = lib.mkIf cfg.enable {
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [printerDomain];

    # Firewall: allow CUPS on VPN interface
    networking.firewall.interfaces.${vpnInterface}.allowedTCPPorts = [631];

    # ipp-usb: USB printer on localhost only
    services.ipp-usb.enable = true;
    boot.blacklistedKernelModules = ["usblp"];
    environment.etc."ipp-usb/ipp-usb.conf".text = ''
      [network]
      interface = loopback
      http-min-port = ${toString ippUsbPort}
      http-max-port = ${toString (ippUsbPort + 10)}
      dns-sd = disable
    '';

    # CUPS: print server on VPN IP, forwarding to ipp-usb
    services.printing = {
      enable = true;
      listenAddresses = ["${cfg.ip}:631"];
      allowFrom = ["all"];
      browsing = true;
      defaultShared = true;
      # Disable cups-browsed to avoid _printer._tcp "Unknown" queues
      browsed.enable = false;
      extraConf = ''
        # Share printers to VPN clients
        <Location />
          Order allow,deny
          Allow from all
        </Location>
        <Location /admin>
          Order allow,deny
          Allow from localhost
        </Location>
        <Location /admin/conf>
          Order allow,deny
          Allow from localhost
        </Location>
      '';
    };

    # Create the printer queue pointing to ipp-usb
    hardware.printers = {
      ensurePrinters = [{
        name = printerName;
        deviceUri = "ipp://localhost:${toString ippUsbPort}/ipp/print";
        model = "everywhere";
        description = "Brother DCP-T730DW";
        location = "Home";
      }];
      ensureDefaultPrinter = printerName;
    };

    # Avahi: advertise CUPS printer on VPN (no _printer._tcp)
    services.avahi = {
      enable = true;
      publish = {
        enable = true;
        userServices = true;
      };
      allowInterfaces = [vpnInterface];
    };
  };
}
```

---

## Key Changes from Current Implementation

1. **Remove nginx proxy** - CUPS handles port 631 directly
2. **Add CUPS server** - `services.printing` with VPN IP listen address
3. **Add printer queue** - `hardware.printers.ensurePrinters` creates queue automatically
4. **Simplify Avahi** - Remove custom XML, let CUPS handle DNS-SD if needed

---

## Verification

After deploy:
1. `lpstat -h brother.krejci.io -p` should show the printer
2. GNOME Settings → Printers → enter "brother.krejci.io" → shows printer
3. User can add and print
4. Android can print via hostname

---

## References
- GNOME discovers via CUPS browsing or mDNS
- `lpstat -h hostname` queries remote CUPS server
- IPP Everywhere requires CUPS 2.2.8+ for driverless
- cups-browsed _printer._tcp causes GNOME "Unknown" queues

---

## Historical Notes (from earlier debugging)

### Hardware
Brother DCP-T730DW connected via USB to thinkcenter. Supports IPP-over-USB (USB class 7/1/4).

### CVE-2009-0164 Host Header Issue
CUPS rejects localhost connections with external Host headers.

**Why nginx proxy doesn't work:**
Even with Unix socket proxy, CUPS returns `printer-uri: ipp://localhost/...` in responses because it determines the URI from the connection source, not ServerName. Clients then try to connect to localhost on their own machine, which fails.

**Working solution:** CUPS must listen on VPN IP directly so it returns correct printer-uri in responses.

### Why PPD Downloads Should Be Blocked
PPD downloads blocked because clients would search for custom Brother driver package not available on client machines. Blocking PPD forces driverless mode.

### cups-browsed Behavior
- Discovers `_printer._tcp` (LPD) from ipp-usb → creates broken "Unknown" queues
- With cups-browsed disabled, CUPS 2.2.4+ discovers `_ipp._tcp` directly
- cups-browsed had vulnerabilities disclosed in late 2024

### Desktop Client Config
```nix
services.printing.enable = true;
services.printing.browsed.enable = false;  # Prevents broken queues
hardware.sane.enable = true;
hardware.sane.extraBackends = [pkgs.sane-airscan];
services.avahi.enable = true;
services.avahi.nssmdns4 = true;
```

### What Failed Earlier
1. CUPS + Brother driver + nginx proxy - Complex, GUI still asked for drivers
2. Custom Avahi `_universal` subtype - Didn't help
3. PPD blocking - Forced driverless for CLI but GUI still problematic

### Useful Commands
```bash
# Check printer from client
lpstat -h brother.krejci.io -p

# Test IPP endpoint
ipptool -tv ipp://brother.krejci.io:631/printers/Brother-DCP-T730DW get-printer-attributes.test

# Browse mDNS services
avahi-browse -a | grep -i printer

# Manual queue creation (for reference only, not for users)
lpadmin -p Brother -v "ipp://brother.krejci.io:631/printers/Brother-DCP-T730DW" -m everywhere -E
```

### External References
- [Debian CUPSDriverlessPrinting](https://wiki.debian.org/CUPSDriverlessPrinting)
- [CUPS New Architecture](https://wiki.debian.org/CUPSNewArchitecture)
- [PAPPL - Printer Application Framework](https://www.msweet.org/pappl/)
- [system-config-printer IPP Everywhere issue](https://github.com/OpenPrinting/system-config-printer/issues/125)

---

## Session 2026-01-05: Verified Findings

### CUPS URI Paths (Verified from cups.org/doc/spec-ipp.html)

CUPS only supports these paths:
- `/` - Server root, CUPS-Get-Printers operation
- `/admin/` - Administration
- `/printers/<name>` - Printer queue
- `/classes/<name>` - Printer class
- `/jobs/<id>` - Job operations

CUPS does NOT support IPP Everywhere paths (`/ipp/print`, `/ipp/printer`).

### nginx Proxy with Host Header Preservation

When nginx proxies to ipp-usb with `proxy_set_header Host $host:$server_port;`, ipp-usb returns the correct external URI in `printer-uri-supported`. Without Host header preservation, ipp-usb returns localhost URI.

tcpdump evidence from nginx proxy test:
```
POST /ipp/print HTTP/1.1
Host: brother.krejci.io:631

HTTP/1.1 200 OK
Server: nginx
printer-uri-supported: ipp://brother.krejci.io:631/ipp/print
```

Android successfully received printer attributes with correct URI. However, Android still shows "unavailable" after first print due to mDNS dependency for availability refresh.

### Current Architecture (CUPS on VPN IP)

CUPS listening directly on VPN IP:631 works for GNOME:
- `lpstat -h brother.krejci.io -p` shows printer
- GNOME enters hostname, queries `/` with CUPS-Get-Printers, finds queue

Android cannot use CUPS by hostname because:
- Android queries `/ipp/print`, `/ipp/printer`, `/ipp` (IPP Everywhere paths)
- CUPS returns 404 for all these paths
- Android manual entry with full path works: `brother.krejci.io:631/printers/Brother-DCP-T730DW`

### Two Architecture Options

1. **CUPS on VPN IP** (current)
   - GNOME works by hostname
   - Android requires full path manual entry
   - Printing works once added

2. **nginx proxy to ipp-usb**
   - Android can discover via `/ipp/print`
   - ipp-usb returns correct URI with Host header preservation
   - Android shows "unavailable" after first print (mDNS dependency)
   - GNOME cannot discover (no CUPS-Get-Printers support in ipp-usb)

Neither architecture satisfies both GNOME hostname discovery AND Android hostname discovery simultaneously.

### Potential Solution: nginx Path-Based Routing

Combine both backends with nginx routing by path:
- `/ipp/*` → ipp-usb (Android IPP Everywhere paths)
- `/` and `/printers/*` → CUPS (GNOME discovery and CUPS paths)

nginx config sketch:
```nginx
server {
    listen 192.168.91.5:631;

    # IPP Everywhere paths for Android
    location /ipp/ {
        proxy_pass http://127.0.0.1:60000;
        proxy_set_header Host $host:$server_port;
    }

    # CUPS paths for GNOME
    location / {
        proxy_pass http://127.0.0.1:631;
        proxy_set_header Host $host:$server_port;
    }
}
```

**Untested.** Risk: CUPS may still return localhost URIs even with Host header. Need to verify CUPS respects ServerName for printer-uri in responses.
