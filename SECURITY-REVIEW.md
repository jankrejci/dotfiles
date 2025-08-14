# Security Review and Improvement Report

## Executive Summary
This repository contains a well-structured NixOS multi-host configuration with some security concerns that need addressing. While the overall architecture follows good practices, there are several vulnerabilities and areas for improvement.

## Critical Security Issues

### 1. **Hardcoded Password Hash Exposure**
- **Location**: `users/jkr.nix:17`
- **Issue**: User password hash is hardcoded in the repository
- **Risk**: High - Password hashes can be cracked offline
- **Recommendation**: Move password hashes to SOPS secrets or use SSH-only authentication

### 2. ~~SSH Key Fetching from Public GitHub~~ [MITIGATED]
- **Location**: `modules/ssh.nix:21`
- **Issue**: SSH keys are fetched from public GitHub repository without signature verification
- **Risk**: ~~Critical~~ Low - MITM attacks could inject malicious SSH keys
- **Mitigation**: 
  - SSH access is only available through WireGuard VPN (defense in depth)
  - HTTPS transport provides server authentication and encryption
  - Added Cache-Control header to prevent stale keys from proxy caches
  - Risk accepted for home network use with VPN-only access
- **Original Recommendations**:
  - Implement signature verification for fetched keys
  - Use a private repository or encrypted storage
  - Consider embedding keys in SOPS secrets

### 3. ~~**Empty SSH Authorized Keys Files**~~ [CORRECTED]
- **Location**: Multiple `hosts/*/ssh-authorized-keys.pub` files  
- **Issue**: ~~Empty authorized keys files in repository~~ Files contain SSH keys that are dynamically fetched
- **Risk**: ~~Medium~~ None - Files serve as source for OpenSSH AuthorizedKeysCommand
- **Implementation Details**:
  - System uses `AuthorizedKeysCommand` in `modules/ssh.nix:70-71`
  - Keys fetched from GitHub repository on demand
  - Keys cached in `/var/cache/ssh/` for 1 minute
  - Cache cleaned every 5 minutes via systemd tmpfiles
- **Security**: Dynamic fetching already documented as acceptable risk with VPN-only access

### 4. **Hardcoded Network Endpoints**
- **Location**: `modules/wg-server.nix`, `scripts.nix:216`
- **Issue**: Hardcoded IP addresses (37.205.13.227:51820)
- **Risk**: Low - Information disclosure
- **Recommendation**: Move to configuration variables or SOPS

## Security Best Practices Missing

### 1. ~~**Network Security**~~ [MITIGATED]
- ~~No fail2ban or intrusion detection~~ - Basic fail2ban enabled for defense-in-depth
- ~~SSH allows password authentication (should be key-only)~~ - Already configured with `PasswordAuthentication = false` in ssh.nix:68
- ~~No rate limiting on exposed services~~ - Services only exposed within WireGuard VPN network
- ~~DNS queries logged but not monitored~~ - Acceptable for home network with VPN-only access

### 2. **Secret Management**
- SOPS is used but inconsistently
- WireGuard private keys generated and stored temporarily without secure deletion
- Disk encryption passwords stored in `/var/lib/disk-password` during installation

### 3. **Service Hardening**
- Grafana exposed without authentication configuration
- CoreDNS logging enabled but no log rotation configured
- No systemd service sandboxing applied

## Code Quality and Nix Best Practices

### 1. **Good Practices Observed**
- Clean module separation
- Proper use of `mkDefault`, `mkForce`, `mkIf`
- Well-structured flake with clear inputs
- Comprehensive test suite for script library

### 2. **Areas for Improvement**
- Inconsistent error handling in scripts
- Missing `set -euo pipefail` in some shell scripts
- No pre-commit hooks for security checks
- Limited documentation for security model

## Recommendations

### Immediate Actions
1. Remove hardcoded password hashes from repository
2. Implement SSH key signature verification
3. Enable SSH key-only authentication
4. Add fail2ban with proper jail configurations

### Short-term Improvements
1. Implement comprehensive SOPS usage for all secrets
2. Add systemd hardening for all services
3. Configure proper firewall rules per host
4. Add security scanning to CI/CD pipeline

### Long-term Enhancements
1. Implement zero-trust network architecture
2. Add centralized logging and monitoring
3. Regular security audits and dependency updates
4. Implement proper backup and disaster recovery

## Positive Security Aspects
- TPM-based disk encryption support
- WireGuard VPN for secure connectivity
- Proper user/group separation
- Firewall enabled by default
- SOPS integration for secret management
- SSH access restricted to VPN-only (defense in depth)
- SSH keys fetched over HTTPS with cache-control headers

## Conclusion
The repository shows good architectural decisions but needs immediate attention to critical security issues, particularly around ~~SSH key management and~~ password storage. The SSH key fetching risk has been mitigated through VPN-only access and is acceptable for a home network environment. With the remaining recommended improvements, this would be a robust and secure NixOS configuration.

## Completed Mitigations
1. **SSH Key Fetching** - Risk accepted with VPN-only access providing defense in depth. Added cache-control headers to prevent proxy caching issues.
2. **Network Security** - Basic fail2ban enabled for internal threat protection. SSH already configured for key-only authentication. Services protected by WireGuard VPN.