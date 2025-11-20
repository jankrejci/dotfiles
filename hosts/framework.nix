{...}: {
  boot = {
    kernelModules = ["kvm-amd"];
    # Better support for sleep states
    kernelParams = [
      "mem_sleep_default=deep"
      # More stable performance for AMD models (if applicable)
      # "amd_pstate=active"
      "usbcore.autosuspend=-1"
    ];
  };

  hardware.cpu.amd.updateMicrocode = true;
}
