{
  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    enableBashIntegration = true;
    settings = {
      c = {
        symbol = " ";
      };
      directory = {
        truncation_length = 1;
        read_only = "🔒";
      };
      git_branch = {
        symbol = " ";
      };
      os.symbols = {
        NixOS = "❄️ ";
        Arch = " ";
        Debian = " ";
        Linux = " ";
        Macos = " ";
        Raspbian = " ";
        Ubuntu = " ";
        Unknown = " ";
        Windows = "🪟 ";
      };
      package = {
        symbol = "📦 ";
        disabled = true;
      };
      python = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
        format = "[ $version](red bold)";
      };
    };
  };
}
