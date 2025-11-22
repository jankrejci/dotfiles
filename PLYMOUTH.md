# Plymouth Boot Splash Screen

Plymouth provides a graphical boot splash screen for NixOS systems.

## Current Configuration

**Location:** `modules/desktop.nix`

**Theme:** `bgrt` (Default NixOS theme - testing for resolution issues)

## Configuration Details

```nix
boot = {
  consoleLogLevel = 0;
  initrd.verbose = false;
  initrd.kernelModules = ["amdgpu"];  # GPU driver loaded in initrd (see hosts/framework.nix)
  kernelParams = [
    "quiet"
    "loglevel=0"  # Suppress all kernel messages except emergencies
    "splash"
    "boot.shell_on_fail"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_level=3"
    "vt.global_cursor_default=0"
    "plymouth.debug"  # Enable debug logging to /var/log/plymouth-debug.log
    "plymouth.use-simpledrm=0"  # Use native amdgpu instead of simpledrm
  ];
  plymouth = {
    enable = true;
    theme = "bgrt";
  };
};
```

## Critical Requirements

### GPU Driver in initrd

**CRITICAL:** Plymouth requires the GPU driver loaded in initrd:
```nix
boot.initrd.kernelModules = ["amdgpu"];  # Framework AMD 7040 series
```

Without amdgpu in initrd:
- Plymouth waits ~3 seconds for hardware detection to load amdgpu
- Delayed splash screen appearance
- Works eventually, but slower boot experience

**Note on thunderbolt module:**
- Thunderbolt loads automatically via hardware detection in initrd
- No need to explicitly include in `initrd.kernelModules`
- External USB-C displays work without explicit configuration

### Flicker-Free Boot

For smooth UEFI→Plymouth transition with no text flashing:
```nix
consoleLogLevel = 0;  # Suppress kernel messages
kernelParams = [
  "quiet"
  "loglevel=0"  # Suppress all kernel messages except emergencies
  "splash"
  "rd.systemd.show_status=false"  # Hide initrd systemd
  "systemd.show_status=false"  # Hide main system systemd
  "rd.udev.log_level=3"
  "udev.log_level=3"
  "vt.global_cursor_default=0"  # Disable cursor blink
];
```

**Testing Results (2025-11-22):**
- Iteration 1: Added `loglevel=3` + `fbcon=nodefer` - resulted in no splash screen and boot messages still visible
- Root cause: `fbcon=nodefer` prevents Plymouth from grabbing framebuffer, `loglevel=3` still shows warnings/errors
- Iteration 2: Changed to `loglevel=0` and removed `fbcon=nodefer` - splash screen works, messages suppressed
- Iteration 3: Added `plymouth.use-simpledrm=0` - forces native amdgpu driver instead of simpledrm
- Iteration 4: Added `console=tty2` to redirect kernel messages away from Plymouth's tty1 - **Plymouth rendered but was not visible on screen**
- Root cause: `console=tty2` redirects the visible console to tty2, but Plymouth uses tty1, resulting in blank screen
- Iteration 5: Removed `console=tty2` - testing in progress

**CRITICAL: Do NOT use `console=ttyN` parameter** - Plymouth uses tty1 and needs it to be the active console. Redirecting console output prevents Plymouth from being visible.

**Note:** Do NOT use `fbcon=nodefer` (prevents Plymouth from working) or `fbcon=map:1` (disables console entirely).

Based on Fedora's FlickerFreeBoot implementation.

### SimpleDRM vs Native Driver

**Problem:** On UEFI systems, simpledrm claims the framebuffer early (at ~0.5s), but Plymouth waits for the native amdgpu driver to load (at ~2s), causing a 1.5-2 second delay even with amdgpu in initrd.

**Solution:** Use `plymouth.use-simpledrm=0` to tell Plymouth to skip simpledrm and wait for the native driver:

```nix
kernelParams = [
  "plymouth.use-simpledrm=0"  # Force native amdgpu driver instead of simpledrm
];
```

**Why this works:**
- simpledrm loads at 0.557s (UEFI framebuffer)
- amdgpu loads at 2.057s (native driver with full modesetting)
- Without this parameter, Plymouth tries simpledrm first, creating /dev/dri/renderD128 (render-only, no modesetting)
- Plymouth then retries with /dev/dri/card1 (amdgpu, full KMS support) - wasting ~2 seconds
- With `plymouth.use-simpledrm=0`, Plymouth waits for amdgpu directly, no wasted attempts

**Trade-off:** Plymouth may start slightly later (waiting for amdgpu), but boot is cleaner with no driver handoff or failed device attempts.

## External Monitor Support

### USB-C/Thunderbolt External Displays

External monitors connected via USB-C/Thunderbolt work automatically with Plymouth:
- Thunderbolt module loads via hardware detection in initrd (at ~0.9s)
- No explicit configuration needed in `initrd.kernelModules`
- Both built-in and external displays show Plymouth splash screen

**Tested configuration (Framework AMD 7040):**
- Built-in display: 2880x1920 (scaled to 1440x960 by Plymouth)
- External display: 2560x1440
- Both displays active during boot with amdgpu driver

**IMPORTANT:** Do NOT use `video=DP-*:e` parameters on Framework laptops.

**Why:**
- Framework doesn't have physical DP-1 through DP-4 connectors
- `:e` flag forces EDID reads on non-existent ports
- Each timeout takes 3-4 seconds → 40+ second boot delays
- dmesg shows repeated `*ERROR* Failed to read EDID`
- USB-C DisplayPort alt-mode works automatically without forcing

## Boot Menu Access

**File:** `modules/disk-tpm-encryption.nix:78-90`

Default systemd-boot behavior (no timeout set):
- Menu hidden by default
- Press **Space** or **ESC** during Plymouth splash to show systemd-boot menu
- Menu shows NixOS generation list for selection

## Available Themes

From `nix search nixpkgs plymouth`:

- **breeze-plymouth** - KDE Breeze theme (current, works fine)
- **bgrt** - Default NixOS theme (fallback option)
- **nixos-bgrt-plymouth** - BGRT theme with spinning NixOS logo
- **adi1090x-plymouth-themes** - Collection of custom themes
- **catppuccin-plymouth** - Catppuccin pastel themes
- **plymouth-matrix-theme** - Matrix-inspired theme
- Other specialty themes available

## Troubleshooting

### No Plymouth Splash Screen

Check if GPU driver is loaded in initrd:
```bash
lsinitrd | grep amdgpu  # Should show amdgpu.ko module
dmesg | grep plymouth  # Check for Plymouth startup
```

Fix: Ensure `boot.initrd.kernelModules = ["amdgpu" "thunderbolt"];` is set.

### Text Flashing During Boot

Ensure all kernel parameters are set for flicker-free boot:
- `consoleLogLevel = 0`
- `rd.systemd.show_status=false`
- `systemd.show_status=false`

### Slow Boot with EDID Errors

Remove any `video=DP-*:e` parameters - they cause delays on non-existent ports.

### Resolution Issues on External Monitors

Enable Plymouth debugging to diagnose resolution problems:
```nix
boot.kernelParams = [ "plymouth.debug" ];
```

After boot, check debug log:
```bash
sudo cat /var/log/plymouth-debug.log
```

If external monitor shows wrong resolution, try:
1. Switch to `bgrt` theme (simpler, better GOP framebuffer support)
2. Verify `plymouth.use-simpledrm=0` is set (forces native amdgpu instead of UEFI framebuffer)

### Testing After Configuration Changes

**After modifying plymouth configuration, test the boot process:**

```bash
# 1. Rebuild boot configuration (faster than switch, changes take effect on reboot)
sudo nixos-rebuild boot

# 2. Reboot to test plymouth behavior
sudo reboot

# 3. After reboot, check if plymouth showed on screen during boot (visual confirmation)

# 4. Check plymouth debug log to verify rendering occurred
sudo cat /var/log/plymouth-debug.log | grep -E "(showing splash|renderD|simpledrm|amdgpu|error|fail)" -i

# 5. Check kernel messages for driver loading sequence
sudo dmesg | grep -E "(simpledrm|amdgpu|drm)" | head -40

# 6. Verify amdgpu loaded early in initrd (should be ~2-3 seconds)
sudo dmesg | grep "amdgpu.*modesetting enabled"

# 7. Check plymouth service status (USR1 signal is normal - means successful completion)
sudo journalctl -b -u plymouth-start.service
```

**Expected behavior with `plymouth.use-simpledrm=0`:**
- Plymouth log should NOT attempt /dev/dri/renderD128 (simpledrm render-only device)
- Plymouth log should directly open /dev/dri/card1 (amdgpu with full KMS)
- dmesg should show amdgpu loading around 2 seconds (normal for initrd)
- No "Could not query rendering device" errors for renderD128

**If boot messages still appear:**
- Check `consoleLogLevel = 0` is set
- Verify `loglevel=0` in kernelParams (not loglevel=3)
- Ensure `rd.systemd.show_status=false` and `systemd.show_status=false` are present

## Smooth Transition to GDM

**GDM has native Plymouth support** - no additional configuration needed.

### How It Works

GDM's systemd service (`gdm.service`) includes built-in Plymouth integration:
- `After=plymouth-start.service` - waits for Plymouth to initialize
- `Conflicts=plymouth-quit.service` - takes over Plymouth quit responsibility
- `OnFailure=plymouth-quit.service` - ensures Plymouth stops if GDM fails
- GDM calls `plymouth quit` internally at the appropriate time

### Virtual Terminal Configuration

- Plymouth: uses VT1 (tty1)
- GDM: uses VT7 (tty7) in NixOS (controlled by `-Dinitial-vt=7` meson flag)
- Handoff between different VTs is handled automatically by GDM

### Expected Behavior

With current configuration (`bgrt` theme + flicker-free boot parameters), the transition should be smooth with minimal flicker. Any brief flash during handoff is typically due to:
- Resolution change (UEFI framebuffer → native mode)
- Mode switch delay between Plymouth quit and GDM start
- GDM's internal 20-second delay before calling `plymouth quit` (historical Wayland workaround)

No additional configuration required - the integration works out of the box.

## References

- NixOS Wiki: https://wiki.nixos.org/wiki/Plymouth
- NixOS Module: `nixpkgs/nixos/modules/system/boot/plymouth.nix`
- Fedora FlickerFreeBoot: https://fedoraproject.org/wiki/Changes/FlickerFreeBoot
- GDM Plymouth Integration: Built into upstream GDM systemd service
