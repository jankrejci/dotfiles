{
  programs.firefox = {
    enable = true;
  };

  xdg.desktopEntries."firefox" = {
    name = "Firefox";
    genericName = "Web Browser";
    comment = "Terminal emulator";
    icon = "firefox";
    exec = "nixGL firefox --name firefox %U";
    categories = [ "Network" "WebBrowser" ];
    terminal = false;
    mimeType = [
      "text/html"
      "text/xml"
      "application/xhtml+xml"
      "application/vnd.mozilla.xul+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    startupNotify = true;
    type = "Application";
  };

}

