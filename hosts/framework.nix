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
}
