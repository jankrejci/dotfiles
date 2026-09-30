# Framework 13 AMD laptop hardware overrides
#
# - amdgpu loaded early for Plymouth
# - deep sleep and USB autosuspend disabled
# - AMD microcode updates
{...}: {
  boot = {
    kernelModules = ["kvm-amd"];
    # Load amdgpu early in initrd so plymouth can use native driver immediately.
    # Without this, plymouth waits ~3s for amdgpu to load via hardware detection.
    initrd.kernelModules = ["amdgpu"];
    # Better support for sleep states
    kernelParams = [
      "mem_sleep_default=deep"
      "usbcore.autosuspend=-1"
    ];
  };

  hardware.cpu.amd.updateMicrocode = true;

  # This board runs without a battery, so fwupd's power check finds no charge
  # level to compare against its threshold and refuses every capsule. Framework
  # supports battery-less updates from 3.20 onward as long as a charger stays
  # attached for the whole flash. The setting lives here and not in the shared
  # notebook module because the other notebooks do have a battery.
  services.fwupd.daemonSettings.IgnorePower = true;
}
