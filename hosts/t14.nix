{config, ...}: {
  hardware.cpu.amd.updateMicrocode = true;

  # ThinkPad-specific kernel modules for ACPI features and power management
  boot.initrd.availableKernelModules = ["thinkpad_acpi" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = ["acpi_call"];
  boot.extraModulePackages = with config.boot.kernelPackages; [acpi_call];
}
