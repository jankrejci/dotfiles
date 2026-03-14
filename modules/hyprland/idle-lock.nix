# Screen lock and idle management
#
# - hyprlock for screen lock with blurred screenshot
# - hypridle for idle timeout chain: dim → lock → dpms off → suspend
{config, ...}: let
  colorsDark = config.colorScheme.darkPalette;
in {
  # Screen lock with blurred background
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 5;
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }
      ];
      input-field = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 2;
          outer_color = "rgb(${colorsDark.base0D})";
          inner_color = "rgb(${colorsDark.base00})";
          font_color = "rgb(${colorsDark.base05})";
          fade_on_empty = true;
          placeholder_text = "";
          dots_center = true;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # Idle timeout chain: dim after 5min, lock after 15min, dpms off after 20min, suspend after 30min on battery only.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "brightnessctl -s set 10%";
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 900;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 1200;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          # Only suspend on battery. Desktop and docked laptop stay awake.
          timeout = 1800;
          on-timeout = "cat /sys/class/power_supply/BAT*/status 2>/dev/null | grep -qi discharging && systemctl suspend";
        }
      ];
    };
  };
}
