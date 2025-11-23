# Plymouth Splash Screen Debugging

## Current Status
Plymouth running successfully with keyboard input working. XKB warning in logs is harmless.

**Handoff fix partially working** - Removed plymouth-quit from display-manager conflicts (modules/desktop.nix:54). Cannot add after/wants dependency on plymouth-quit-wait due to circular dependency causing boot hang.

## Key Findings

### Issues Found

1. **xkbcommon ERROR** (WORKING - warning is harmless):
   - Plymouth logs show error trying default path `/nix/store/.../etc/X11/xkb`
   - **Fix**: Set `XKB_CONFIG_ROOT=/nix/store/.../share/X11/xkb` in plymouth-start.service
   - Added in modules/desktop.nix:45-47
   - Error message still appears (xkbcommon tries default first) but keyboard works correctly

2. **Plymouth to GDM black screen with external monitor** (PARTIAL FIX):
   - Black screen delay during handoff from Plymouth to GDM with USB-C external monitor
   - **Fix**: Removed plymouth-quit from display-manager conflicts (modules/desktop.nix:54)
   - **Cannot use**: after/wants on plymouth-quit-wait - creates circular dependency
     - display-manager waits for plymouth-quit-wait
     - plymouth-quit-wait waits for boot completion (multi-user.target)
     - multi-user.target requires display-manager
     - Result: Boot hangs at "Hold until boot process finishes up" for ~56s then timeout
   - Current fix keeps only conflict removal, which still improves handoff timing

3. **Previous Issue** (RESOLVED):
   - Plymouth daemon was starting but exiting immediately
   - Debug logging enabled, shows Plymouth now working correctly
   - Logs show successful start at boot time (modules/desktop.nix:33)

### Configuration Status
- `boot.plymouth.enable = true` ✓
- `boot.plymouth.theme = "bgrt"` ✓
- `boot.initrd.systemd.enable = true` ✓ (set in disk-tpm-encryption.nix:114)
- `boot.initrd.kernelModules = ["amdgpu"]` ✓ (set in hosts/framework.nix:6)
- Kernel parameters include `splash`, `quiet`, `plymouth.use-simpledrm=0`

### Current Logs Analysis
From `journalctl -b -u plymouth-start.service`:
- Plymouth starts at 10:52:55, debug output redirected to /dev/tty1
- **xkbcommon ERROR**: Failed to add default include path (fixed with XKB_CONFIG_ROOT)
- Fontconfig warnings (minor, just cache directory configs)
- Plymouth held splash until 10:53:11 (16 seconds into boot), then quit normally

The splash is working! The xkbcommon error was preventing keyboard input during password prompts.

## Testing Protocol

**IMPORTANT**: Plymouth changes require reboot to test. Before each reboot:
1. Document all changes in this file (PLYMOUTH.md)
2. Commit changes to git in **separate commits**:
   - First commit: code changes only (modules/desktop.nix, etc.)
   - Second commit: documentation changes (PLYMOUTH.md)
3. Then reboot to test
4. After reboot, update this file with test results

## Optional Cleanup

If satisfied with Plymouth working, disable debug logging:
- Remove `plymouth.debug` from modules/desktop.nix:33
- This reduces log verbosity for normal operation

## Boot Timeline (from current logs)
```
[0.559s] simpledrm initialized
[2.065s] amdgpu kernel modesetting enabled
[2.742s] Seamless boot condition check passed
[3.062s] amdgpu initialized
[4.996s] plymouth-start.service starting (main system, not initrd)
```

## Relevant Files
- modules/desktop.nix - Plymouth configuration and kernel params
- modules/disk-tpm-encryption.nix:114 - boot.initrd.systemd.enable
- hosts/framework.nix:6 - initrd.kernelModules = ["amdgpu"]

## Commands Used
```bash
# Check if Plymouth running
plymouth --ping

# View Plymouth logs
sudo journalctl -b -u plymouth-start.service
sudo journalctl -b | grep -i plymouth

# Check DRM/graphics initialization
sudo dmesg | grep -i drm
sudo dmesg | grep -i plymouth

# List boot sessions
sudo journalctl -b --list-boots
```
