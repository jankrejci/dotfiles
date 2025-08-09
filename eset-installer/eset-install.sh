#!/usr/bin/env bash
#
# ESET PROTECT Agent Installer for NixOS
#
# This script installs ESET PROTECT Agent on NixOS systems by:
# 1. Running the installer in an FHS environment
# 2. Patching binaries for NixOS compatibility
# 3. Creating a consistent service configuration
#
# Usage: sudo ./eset-install.sh
#
# Requirements:
# - Must be run as root
# - Requires eset-env.nix in the same directory
# - Requires PROTECTAgentInstaller.sh in the same directory

set -euo pipefail

#============================================================================
# Configuration
#============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/eset-installer-$$"
readonly ESET_AGENT_PATH="/opt/eset/RemoteAdministrator/Agent"
readonly ESET_CONFIG_PATH="/etc/opt/eset/RemoteAdministrator/Agent"
readonly ESET_DATA_PATH="/var/opt/eset/RemoteAdministrator/Agent"
readonly ESET_LOG_PATH="/var/log/eset/RemoteAdministrator/Agent"

#============================================================================
# Utility Functions
#============================================================================

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_step() {
	echo
	log "=== $* ==="
}

error_exit() {
	echo "ERROR: $*" >&2
	exit 1
}

check_root() {
	# Verify script is running with root privileges
	# ESET requires root access to install system services and modify protected directories
	if [ "$EUID" -ne 0 ]; then
		error_exit "This script must be run as root"
	fi
}

cleanup() {
	# Remove all temporary files created during installation
	# This function is called automatically on script exit (trap)
	log "Cleaning up temporary files..."
	rm -rf "$TEMP_DIR" 2>/dev/null || true
	rm -f /tmp/run-in-fhs.sh 2>/dev/null || true
	rm -f /tmp/eset-config-backup.tar.gz 2>/dev/null || true
	rm -f /tmp/patchelf 2>/dev/null || true
}

#============================================================================
# Installation Functions
#============================================================================

cleanup_previous_installation() {
	# Stop any running ESET services and clean previous installation data
	# This ensures a clean slate for the new installation
	log_step "Cleaning up previous installation attempts"

	# Stop all possible ESET service variants
	systemctl stop eset 2>/dev/null || true
	systemctl stop eset-agent 2>/dev/null || true
	systemctl stop eraagent 2>/dev/null || true

	# Clear previous configuration and data files
	rm -rf "${ESET_CONFIG_PATH:?}"/* 2>/dev/null || true
	rm -rf "${ESET_DATA_PATH:?}"/* 2>/dev/null || true
	rm -rf "${ESET_LOG_PATH:?}"/* 2>/dev/null || true
}

create_directories() {
	# Create all required directories for ESET installation
	# These directories follow ESET's standard Linux installation layout
	log_step "Creating directory structure"

	mkdir -p "$ESET_CONFIG_PATH"  # Configuration files
	mkdir -p "$ESET_DATA_PATH"    # Runtime data and state
	mkdir -p "$ESET_LOG_PATH"     # Log files
	mkdir -p "$TEMP_DIR"          # Temporary installation files
}

build_fhs_environment() {
	# Build a Filesystem Hierarchy Standard (FHS) environment using Nix
	# This creates a container-like environment where the ESET installer
	# can find expected system directories and libraries
	log_step "Building FHS environment"

	if [ ! -f "$SCRIPT_DIR/eset-env.nix" ]; then
		error_exit "eset-env.nix not found in $SCRIPT_DIR"
	fi

	log "Building Nix FHS environment..."
	ESET_ENV=$(nix-build "$SCRIPT_DIR/eset-env.nix" --no-out-link)

	if [ ! -d "$ESET_ENV" ]; then
		error_exit "Failed to build FHS environment"
	fi

	log "FHS environment ready: $ESET_ENV"
}

create_fhs_script() {
	# Create a script to run inside the FHS environment
	# This script sets up the environment and runs the ESET installer
	log "Creating FHS installation script..."

	cat >/tmp/run-in-fhs.sh <<'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Running inside FHS environment ==="

# Create required directories
mkdir -p /opt/eset/RemoteAdministrator/Agent
mkdir -p /etc/init.d
mkdir -p /etc/systemd/system
mkdir -p /etc/opt/eset/RemoteAdministrator/Agent
mkdir -p /var/opt/eset/RemoteAdministrator/Agent
mkdir -p /var/log/eset/RemoteAdministrator/Agent

# Create dummy sudo to bypass PAM issues in FHS
create_sudo_bypass() {
    cat > /tmp/sudo-bypass << 'SUDO_EOF'
#!/bin/sh
# Bypass sudo for FHS environment
if [ "$1" = "-E" ]; then
    shift
fi
exec "$@"
SUDO_EOF
    chmod +x /tmp/sudo-bypass
    export PATH="/tmp:$PATH"
    ln -sf /tmp/sudo-bypass /tmp/sudo
}

create_sudo_bypass

# Clean sudo environment variables
unset SUDO_COMMAND SUDO_USER SUDO_UID SUDO_GID 2>/dev/null || true

# Run the ESET installer
cd /tmp/eset-installer-files
echo "Running ESET PROTECT Agent installer..."
./PROTECTAgentInstaller.sh

# Preserve installation artifacts
echo "=== Preserving installation artifacts ==="
tar -czf /tmp/eset-config-backup.tar.gz \
    /etc/opt/eset/RemoteAdministrator/Agent/* \
    /var/opt/eset/RemoteAdministrator/Agent/* \
    /opt/eset/RemoteAdministrator/Agent/*.cfg \
    /opt/eset/RemoteAdministrator/Agent/*.ini \
    /tmp/tmp.*.peer.pfx \
    /tmp/tmp.*.ca \
    2>/dev/null || true

echo "Configuration backed up successfully"
EOF

	chmod +x /tmp/run-in-fhs.sh
}

run_installer_in_fhs() {
	# Execute the ESET installer within the FHS environment
	# The FHS environment provides the expected filesystem layout and libraries
	# that the installer expects on a traditional Linux system
	log_step "Running installer in FHS environment"

	if [ ! -f "$SCRIPT_DIR/PROTECTAgentInstaller.sh" ]; then
		error_exit "PROTECTAgentInstaller.sh not found in $SCRIPT_DIR"
	fi

	# Copy installer files to temporary location accessible from FHS
	cp -r "$SCRIPT_DIR"/* "$TEMP_DIR"/
	ln -sf "$TEMP_DIR" /tmp/eset-installer-files

	create_fhs_script

	log "Executing installer in FHS environment..."
	"$ESET_ENV/bin/eset-installer-env" /tmp/run-in-fhs.sh
}

restore_configuration() {
	# Extract configuration files created by the installer in FHS environment
	# The FHS environment can't directly access host filesystem, so we backup
	# and restore the configuration files that were created during installation
	log_step "Restoring configuration from FHS environment"

	if [ ! -f /tmp/eset-config-backup.tar.gz ]; then
		error_exit "Configuration backup not found - installation may have failed"
	fi

	log "Extracting preserved configuration..."
	tar -xzf /tmp/eset-config-backup.tar.gz -C / 2>/dev/null || true

	# Set proper ownership for all ESET directories
	chown -R root:root /etc/opt/eset 2>/dev/null || true
	chown -R root:root /var/opt/eset 2>/dev/null || true
	chown -R root:root /var/log/eset 2>/dev/null || true

	log "Configuration restored successfully"
}

install_patchelf() {
	# Ensure patchelf is available for binary modification
	# patchelf is required to modify ELF binaries for NixOS compatibility
	if command -v patchelf &>/dev/null; then
		PATCHELF="patchelf"
		return
	fi

	log "Installing patchelf..."
	nix-shell -p patchelf --run "cp \$(which patchelf) /tmp/patchelf"
	chmod +x /tmp/patchelf
	PATCHELF="/tmp/patchelf"
}

get_nix_library_paths() {
	# Resolve paths to Nix-managed system libraries
	# These paths are needed to set up the runtime library path (RPATH)
	# for the ESET binaries to find required libraries in NixOS
	log "Resolving Nix library paths..."

	GLIBC_PATH=$(nix-build --no-out-link '<nixpkgs>' -A glibc)
	OPENSSL_PATH=$(nix-build --no-out-link '<nixpkgs>' -A openssl.out)
	ZLIB_PATH=$(nix-build --no-out-link '<nixpkgs>' -A zlib.out)
	STDCPP_PATH=$(nix-build --no-out-link '<nixpkgs>' -A stdenv.cc.cc.lib)

	log "Library paths resolved:"
	log "  glibc: $GLIBC_PATH"
	log "  openssl: $OPENSSL_PATH"
	log "  zlib: $ZLIB_PATH"
	log "  stdcpp: $STDCPP_PATH"
}

patch_eset_binaries() {
	# Modify ESET binaries to work with NixOS's unique filesystem layout
	# NixOS doesn't use standard paths like /lib64, so we patch the binaries
	# to use the correct interpreter and library paths from Nix store
	log_step "Patching ESET binaries for NixOS compatibility"

	if [ ! -f "$ESET_AGENT_PATH/ERAAgent" ]; then
		error_exit "ESET Agent binary not found at $ESET_AGENT_PATH/ERAAgent"
	fi

	install_patchelf
	get_nix_library_paths

	# Backup original binary before modification
	log "Creating backup of original binary..."
	cp "$ESET_AGENT_PATH/ERAAgent" "$ESET_AGENT_PATH/ERAAgent.orig"

	# Patch the main ERAAgent binary
	log "Patching ERAAgent binary..."
	log "  Setting interpreter..."  # Set the dynamic linker path
	"$PATCHELF" --set-interpreter "$GLIBC_PATH/lib/ld-linux-x86-64.so.2" "$ESET_AGENT_PATH/ERAAgent"

	log "  Setting RPATH..."  # Set runtime library search paths
	local rpath="$ESET_AGENT_PATH:$GLIBC_PATH/lib:$OPENSSL_PATH/lib:$ZLIB_PATH/lib:$STDCPP_PATH/lib"
	"$PATCHELF" --set-rpath "$rpath" "$ESET_AGENT_PATH/ERAAgent"

	# Patch all shared libraries used by ESET
	log "Patching shared libraries..."
	find "$ESET_AGENT_PATH" -name "*.so" -type f | while read -r lib; do
		log "  Patching: $(basename "$lib")"
		"$PATCHELF" --set-rpath "$rpath" "$lib" 2>/dev/null || true
	done

	log "Binary patching completed successfully"
}

configure_service() {
	# Ensure systemd service is properly configured with consistent naming
	# The installer may create eraagent.service, but we want to use 'eset' for consistency
	# with NixOS configuration modules
	log_step "Configuring systemd service"

	# Check for various possible service file locations/names
	if [ -f /etc/systemd/system/eraagent.service ]; then
		log "Creating service symlink for consistency..."
		ln -sf /etc/systemd/system/eraagent.service /etc/systemd/system/eset.service
		systemctl daemon-reload
		log "Created symlink: eset.service -> eraagent.service"
	elif [ -f /etc/systemd/system/eset.service ]; then
		log "ESET service already configured as eset.service"
	elif systemctl list-unit-files | grep -q "eset\|eraagent"; then
		log "ESET service detected in systemd, skipping configuration"
	else
		log "Warning: No ESET service file found, but continuing..."
		log "Service may be managed by NixOS configuration"
	fi
}

start_and_verify_service() {
	# Start the ESET service and verify it's running properly
	# This is the final verification that the installation was successful
	log_step "Starting and verifying ESET service"

	log "Starting ESET service..."
	systemctl restart eset
	sleep 3  # Give the service time to start

	log "Service status:"
	systemctl status eset --no-pager || {
		error_exit "Service failed to start properly"
	}

	log "Installation completed successfully!"
}

#============================================================================
# Main Installation Process
#============================================================================

main() {
	log_step "ESET PROTECT Agent Installation for NixOS"

	# Setup trap for cleanup
	trap cleanup EXIT

	# Pre-flight checks
	check_root

	# Installation steps
	cleanup_previous_installation
	create_directories
	build_fhs_environment
	run_installer_in_fhs
	restore_configuration
	patch_eset_binaries
	configure_service
	start_and_verify_service

	log_step "Installation completed successfully!"
	echo
	echo "The ESET PROTECT Agent is now installed and running."
	echo "Service name: eset"
	echo "Check status: systemctl status eset"
	echo "View logs: journalctl -u eset -f"
}

#============================================================================
# Script Entry Point
#============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
