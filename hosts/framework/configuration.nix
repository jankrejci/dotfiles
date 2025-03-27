{ ... }:
{
  boot.kernelModules = [ "kvm-amd" ];

  # Better support for sleep states
  boot.kernelParams = [
    "mem_sleep_default=deep"
    # More stable performance for AMD models (if applicable)
    # "amd_pstate=active"
  ];

  hardware.framework.laptop = {
    enable = true;
    amd.enable = true; # If you have an AMD model
  };

  hardware.cpu.amd.updateMicrocode = true;

  # Enable fingerprint reader (if available on your model)
  services.fprintd.enable = true;

  services.thermald.enable = true;
  powerManagement.powertop.enable = true;

  # Improve battery life
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
    };
  };

  # For better hardware video acceleration
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
}
