# ESET PROTECT Agent on NixOS

Complete guide to install ESET PROTECT Agent on NixOS systems.

## Prerequisites

- NixOS system with root access
- ESET PROTECT Agent installer from your ESET management console
- Internet connection for downloading components

## Step-by-Step Installation

### 1. Run the Complete Installation

Execute the automated installation script that handles FHS environment setup and agent registration:

```bash
sudo ./full-eset-install.sh
```

This script will:
- Create proper FHS environment for the installer
- Download and install the ESET agent
- Register with the ESET PROTECT server
- Preserve all configuration files

### 2. Patch the Binary for NixOS

After installation, patch the agent binary to run natively on NixOS:

```bash
sudo nix-shell -p patchelf --run "./patch-eset-binary.sh"
```

This patches the binary to use NixOS libraries and removes dependency on FHS environment.

### 3. Add NixOS Service Configuration

Copy `eset-final.nix` to your NixOS configuration and add it to your imports:

```nix
# In your configuration.nix or flake
imports = [
  ./path/to/eset-final.nix
];
```

### 4. Rebuild NixOS Configuration

Apply the configuration:

```bash
sudo nixos-rebuild switch
```

**Note:** You may need to reboot after the first rebuild to fully clear any systemd state.

### 5. Verify Installation

Check if the service is running:

```bash
systemctl status eset
```

You should see:
- `Active: active (running)`
- `Loading ... OK`
- `Starting ... OK`

## Troubleshooting

### Service Not Starting

If the service fails to start:

1. **Check the binary exists and is patched:**
   ```bash
   ls -la /opt/eset/RemoteAdministrator/Agent/ERAAgent
   ldd /opt/eset/RemoteAdministrator/Agent/ERAAgent
   ```

2. **Test manual execution:**
   ```bash
   sudo /opt/eset/RemoteAdministrator/Agent/ERAAgent
   ```

3. **Check service logs:**
   ```bash
   journalctl -u eset -n 20
   ```

### Re-installation

If you need to reinstall:

1. Stop the service: `sudo systemctl stop eset`
2. Remove old installation: `sudo rm -rf /opt/eset`
3. Run installation again: `sudo ./full-eset-install.sh`
4. Patch binary again: `sudo nix-shell -p patchelf --run "./patch-eset-binary.sh"`
5. Rebuild NixOS: `sudo nixos-rebuild switch`

## Manual Installation (Alternative)

If the automated script doesn't work, you can install manually:

```bash
# 1. Create FHS environment
sudo ./run-eset-installer.sh

# 2. Inside the FHS environment, run:
./PROTECTAgentInstaller.sh

# 3. Exit and patch binary
exit
sudo nix-shell -p patchelf --run "./patch-eset-binary.sh"

# 4. Add service configuration and rebuild
```

## What Gets Installed

- **Agent binary:** `/opt/eset/RemoteAdministrator/Agent/ERAAgent`
- **Configuration:** `/etc/opt/eset/RemoteAdministrator/Agent/config.cfg`
- **Data:** `/var/opt/eset/RemoteAdministrator/Agent/`
- **Logs:** `/var/log/eset/RemoteAdministrator/Agent/`
- **Service:** `eset.service` (managed by systemd)

## Service Management

```bash
# Check status
systemctl status eset

# View live logs
journalctl -u eset -f

# Restart service
sudo systemctl restart eset

# Stop service
sudo systemctl stop eset

# Start service
sudo systemctl start eset
```

## Important Notes

- The agent requires root privileges to function properly
- Configuration includes server connection details and certificates
- The service automatically starts on boot
- Agent communicates with ESET PROTECT server for policy updates and reporting
- Some cosmetic warnings about missing package files are normal and don't affect functionality