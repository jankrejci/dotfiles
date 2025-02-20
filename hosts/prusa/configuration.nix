{ hostConfig, ... }:
{
  # TODO add obico plugin and enable the port
  services.octoprint = {
    enable = true;
    host = hostConfig.ipAddress;
  };
}

