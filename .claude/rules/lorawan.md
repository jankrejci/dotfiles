---
paths:
  - "homelab/lorawan-*.nix"
---

# LoRaWAN Gateway

See `homelab/lorawan-gateway.nix` for full GNSS architecture documentation.

Key finding: GPS time sync requires working GPIO14 for UART TX to send UBX
commands. Some RPi boards have dead GPIO14. Use RPi 3B, not 3B+.
