{
  config,
  pkgs,
  ...
}: {
  hardware.cpu.amd.updateMicrocode = true;

  # ThinkPad-specific kernel modules for ACPI features and power management
  boot.initrd.availableKernelModules = ["thinkpad_acpi" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = ["acpi_call"];
  boot.extraModulePackages = with config.boot.kernelPackages; [acpi_call];

  # Microphone mute LED synchronization
  #
  # Problem: LED stays constantly on because Pipewire handles mute in software (not ALSA hardware).
  # Kernel LED driver (snd_ctl_led) expects ALSA hardware mute events which Pipewire doesn't send.
  # Kernel modes (follow-mute/follow-route) tested but don't work with Pipewire software mute.
  #
  # Solution: Polling service queries Pipewire state every 200ms and updates LED
  # - WirePlumber Lua hook attempted but failed (sandbox restrictions prevent LED file access)
  # - Event-based approach not viable (wpctl subscribe command doesn't exist)
  # - Polling is efficient: CPU 0.7%, MEM ~0%, response feels instant (5 checks/second)
  # - Works in GDM and user sessions (default.target), syncs all mute sources (F4, GUI, CLI)
  #
  # Grant user write access to LED brightness file
  systemd.tmpfiles.rules = [
    "z /sys/class/leds/platform::micmute/brightness 0666 - - - -"
  ];

  # Polling service: monitor Pipewire mute state and sync LED
  systemd.user.services.mic-mute-led-sync = {
    description = "Sync microphone mute LED with Pipewire state";
    after = ["pipewire.service"];
    wantedBy = ["default.target"];

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "1s";
      ExecStart = pkgs.writeShellScript "mic-mute-led-sync" ''
        readonly LED_PATH="/sys/class/leds/platform::micmute/brightness"
        prev_state=""

        while true; do
          if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | ${pkgs.gnugrep}/bin/grep -q MUTED; then
            current_state="1"
          else
            current_state="0"
          fi

          if [[ "$current_state" != "$prev_state" ]]; then
            echo "$current_state" > "$LED_PATH" 2>/dev/null || true
            prev_state="$current_state"
          fi

          sleep 0.2
        done
      '';
    };
  };
}
