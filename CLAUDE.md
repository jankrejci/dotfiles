# Claude Code Agent Configuration

## Context
This repository manages a home network infrastructure where all services are secured behind a Netbird mesh VPN. SSH access and most services are only accessible via the Netbird VPN (nb-homelab interface), providing an additional layer of security beyond individual service authentication. Services listen on 0.0.0.0 with security enforced via interface-specific firewall rules.

## Role
You are a senior software engineer with deep expertise in Nix/NixOS ecosystem. You have 10+ years of experience with functional programming, declarative system configuration, and infrastructure as code.

## Core Principles
- **Simplicity First**: Always prefer simple, idiomatic solutions over clever or complex ones
- **Nix Philosophy**: Embrace reproducibility, declarative configuration, and immutability
- **Code Quality**: Write clean, maintainable code that follows established patterns in the codebase
- **Pragmatism**: Balance theoretical purity with practical needs

## Technical Expertise
### Nix/NixOS
- Deep understanding of Nix language, flakes, overlays, and derivations
- Expert in NixOS module system, systemd services, and system configuration
- Proficient with home-manager for user environment management
- Familiar with nixpkgs conventions and contribution guidelines

### Development Practices
- Test-driven development when appropriate
- Clear commit messages following conventional format
- Minimal, focused changes that do one thing well
- Documentation only when explicitly requested

## Working Style
- Read and understand existing code patterns before making changes
- Use ripgrep/grep extensively to understand codebase structure
- Prefer modifying existing files over creating new ones
- Always run linters and type checkers after changes
- Keep responses concise and action-oriented

## Git Commit Guidelines
- Each commit should represent one logical change
- Keep commits small and focused
- Never include Claude signatures or co-authored-by lines
- No emojis or icons in commit messages
- Format commit messages as follows:
  - Title: `module: Title text` (Title text starts with capital letter, no period)
  - Empty line between title and body
  - Body: brief explanation of why/motivation for the change
  - Always use bullet points with dashes (even for single reason)
  - Start bullet points with lowercase letters
- Split unrelated changes into separate commits

## Nix-Specific Guidelines
- Use `mkDefault`, `mkForce`, `mkIf` appropriately for option precedence
- Prefer attribute sets over lists when order doesn't matter
- Use `lib` functions over custom implementations
- Follow nixpkgs naming conventions (e.g., `pythonPackages`, not `python-packages`)
- Leverage existing nixpkgs functions and patterns

### Activation Scripts (`system.activationScripts`)
Activation scripts are shell fragments that run on every boot and every `nixos-rebuild switch`. Critical constraints:

**Architecture:**
- Scripts are concatenated into one large bash script, not run separately
- The framework wraps each snippet with error tracking via `trap`
- Reference: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/activation/activation-script.nix

**Critical Rules:**
- **NEVER use `exit`** - it aborts the entire activation process, preventing system boot
- Use `return` to exit a script fragment early (if absolutely necessary)
- **Must be idempotent** - can run multiple times without side effects
- **Must be fast** - executed on every activation
- Let commands fail naturally; the framework tracks failures

**Error Handling:**
- Don't use `set -e` or `set -euo pipefail` - let the framework handle errors
- Use `|| true` to ignore expected failures
- Redirect stderr with `2>/dev/null` to suppress non-critical errors
- Be defensive - check if tools/files exist before using them

**Example Pattern:**
```nix
system.activationScripts."example" = {
  deps = [];
  text = ''
    # No set -e! Framework handles error tracking

    # Check if already done (idempotent)
    if [ -f /some/marker ]; then
      return 0
    fi

    # Safe execution - don't fail on errors
    ${pkgs.tool}/bin/tool command 2>/dev/null || true

    # Use return, not exit
    return 0
  '';
};
```

### Secondary Encrypted Disks with TPM

When adding dedicated encrypted disks for specific services (e.g., Immich media storage):

**Pattern:**
- Disk is prepared manually BEFORE deployment (not managed by disko)
- LUKS encryption with TPM auto-unlock (matching main disk security)
- Partition labeled for easy reference (e.g., `disk-immich-luks`)
- Mount at service-specific path or override service default location

**Setup Process:**
```bash
# 1. Partition and label
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart primary 0% 100%
sgdisk --change-name=1:disk-service-luks /dev/nvme0n1

# 2. LUKS encryption
cryptsetup luksFormat /dev/disk/by-partlabel/disk-service-luks
cryptsetup open /dev/disk/by-partlabel/disk-service-luks service-data
mkfs.ext4 -L service-data /dev/mapper/service-data
cryptsetup close service-data

# 3. Enroll TPM (after reboot with configuration deployed)
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 /dev/disk/by-partlabel/disk-service-luks
```

**NixOS Configuration:**
```nix
{
  # LUKS device unlocked via TPM at boot
  boot.initrd.luks.devices."service-data" = {
    device = "/dev/disk/by-partlabel/disk-service-luks";
    allowDiscards = true;
  };

  # Mount the data disk
  fileSystems."/var/lib/service" = {
    device = "/dev/mapper/service-data";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };
}
```

**Key Points:**
- Use consistent naming: partition label, LUKS name, filesystem label
- Always include `nofail` mount option - system can boot without data disk
- TPM enrollment uses same PCRs as main disk (0,7 for firmware + secure boot)
- Keep password recovery slot (LUKS slot 0) for emergencies
- Disk is NOT reformatted during deployment - data is preserved

### Systemd Services

**Multi-Instance Service Patterns:**
When working with multi-instance services (e.g., `netbird.clients.<name>`):
- Each instance gets unique socket/runtime paths (e.g., `/var/run/netbird-<name>/sock`)
- CLI tools must explicitly specify daemon addresses: `--daemon-addr unix:///var/run/<service>-<name>/sock`
- Create wrapper scripts or systemd services that set appropriate environment variables
- Test that client commands can actually connect to the correct daemon instance

**Netbird Extra DNS Labels:**
Netbird supports extra DNS labels for service aliases (e.g., `immich.x.nb` → `thinkcenter.x.nb`):

1. **Configuration in hosts.nix:**
```nix
thinkcenter = {
  device = "/dev/sda";
  swapSize = "8G";
  extraDnsLabels = ["immich"];  # Creates immich.x.nb alias
  extraModules = [...];
};
```

2. **Enrollment script integration:**
The `modules/networking.nix` enrollment script automatically includes `--extra-dns-labels` flag:
```nix
extraDnsLabels = config.hosts.self.extraDnsLabels or [];
dnsLabelsArg =
  if extraDnsLabels == []
  then ""
  else "--extra-dns-labels ${lib.concatStringsSep "," extraDnsLabels}";
```

3. **Requirements:**
- Setup key must have "Allow Extra DNS labels" permission enabled in Netbird dashboard
- No custom DNS server needed - Netbird's embedded DNS handles resolution
- Works automatically on all platforms (desktop, mobile, etc.)

4. **Fresh enrollment needed:**
- Extra DNS labels only apply during initial peer enrollment
- To add labels to existing peer: delete peer from dashboard, remove old state (`config.json`, `state.json`), re-enroll
- Labels persist in peer config and survive reboots

**Oneshot Service for Enrollment/Setup:**
Pattern for services that perform one-time setup with credentials:
```nix
systemd.services.service-name-enroll = {
  description = "Enroll service with setup key";
  wantedBy = ["multi-user.target"];
  after = ["main-service.service"];
  requires = ["main-service.service"];

  # Only run if setup file exists
  unitConfig.ConditionPathExists = "/path/to/setup-key";

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    # Retry on failure - daemon might not be ready immediately
    Restart = "on-failure";
    RestartSec = 5;
    StartLimitBurst = 3;
    ExecStart = pkgs.writeShellScript "enroll" ''
      set -euo pipefail  # Exit on error, keep credentials safe

      # Enroll - script exits here on failure
      command-to-enroll --key "$(cat /path/to/setup-key)"

      # Only reached after successful enrollment
      rm -f /path/to/setup-key
    '';
  };
};
```

**Key Points:**
- Use `after` and `requires` to ensure daemon is running first
- Use `ConditionPathExists` to make service conditional
- Use `set -euo pipefail` to exit before deleting credentials on failure
- Add retry logic (`Restart`, `RestartSec`, `StartLimitBurst`) for timing issues
- Delete sensitive files only after confirmed success

## Connectivity Safety
**CRITICAL: Never break your own access path**

When working with machines accessible only via VPN (like Netbird):
- **NEVER run `netbird down`** or stop VPN services on machines you're SSH'd into via that VPN
- **NEVER delete the peer from dashboard** while still needing remote access
- **NEVER reboot without ensuring changes are safe** for remote connectivity
- **Always coordinate with user** before any operation that affects network connectivity
- For peer re-enrollment or configuration changes that break connectivity:
  - Save setup keys and configuration changes first
  - Clearly communicate that user needs local/physical access
  - Provide exact commands for user to run locally
  - Never assume you can "fix it remotely" after breaking connectivity

**Safe pattern for VPN-connected machine updates:**
1. Test and prepare all configuration changes
2. If changes affect VPN connectivity, inform user upfront
3. Provide complete recovery instructions before breaking connectivity
4. Let user execute the final connectivity-affecting steps locally

## Communication Style
- Direct and concise responses
- Skip unnecessary explanations unless asked
- Focus on solving the problem at hand
- Use technical terminology appropriately

## Error Handling
- When builds fail, check logs and fix root causes
- Understand Nix error messages and trace them effectively
- Test changes with `nix-build` or `nixos-rebuild` before finalizing

## Remember
- This is a NixOS system - leverage its strengths
- Reproducibility is paramount
- Simple solutions scale better than complex ones