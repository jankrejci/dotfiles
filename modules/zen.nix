# Zen Browser theme for home-manager
#
# Zen's Flatpak cannot detect the system color scheme for web content.
# Its theme system bypasses Firefox's LightweightThemeConsumer, leaving
# browser.theme.content-theme stuck on dark. The XDG portal is also
# unreachable from Gecko's LookAndFeel inside the Flatpak sandbox.
#
# Workaround: a sideloaded WebExtension with an Experiment API polls a
# theme-mode file from the privileged parent process and sets the
# content-override pref directly via Services.prefs. The Experiment API
# bypasses the file:// security restriction that blocks normal extensions
# from reading local files. The userChrome.css uses a -moz-pref media
# query on the same pref to switch the chrome theme in sync.
#
# Profile path is discovered from profiles.ini at activation time. Flatpak
# keeps profiles under ~/.var/app/app.zen_browser.zen/.zen/.
{
  config,
  lib,
  pkgs,
  ...
}: let
  colorsDark = config.colorScheme.palette;
  colorsLight = config.colorScheme.lightPalette;

  xdgConfig = config.xdg.configHome;
  homeDir = config.home.homeDirectory;

  # Path inside the Flatpak sandbox where the extension reads mode.
  # Flatpak maps ~/.zen to the host path under ~/.var/app/.../.zen/.
  themeModeFile = "${homeDir}/.zen/theme-mode";

  extensionId = "zen-theme-toggle@jkr";

  extensionManifest = builtins.toJSON {
    manifest_version = 2;
    name = "Zen Theme Toggle";
    version = "1.0";
    description = "Sync web content color scheme from theme-mode file";
    permissions = [];
    background = {
      scripts = ["background.js"];
    };
    browser_specific_settings = {
      gecko = {
        id = extensionId;
      };
    };
    experiment_apis = {
      themeToggle = {
        schema = "schema.json";
        parent = {
          scopes = ["addon_parent"];
          script = "api.js";
          paths = [["themeToggle"]];
        };
      };
    };
  };

  # Experiment API schema defining the privileged functions available to
  # the background script.
  extensionSchema = builtins.toJSON [
    {
      namespace = "themeToggle";
      functions = [
        {
          name = "readMode";
          type = "function";
          async = true;
          parameters = [
            {
              name = "path";
              type = "string";
            }
          ];
        }
        {
          name = "setColorScheme";
          type = "function";
          async = true;
          parameters = [
            {
              name = "mode";
              type = "string";
            }
          ];
        }
      ];
    }
  ];

  # Experiment API implementation running in the privileged parent process.
  # Has full XPCOM access: IOUtils for file reading, Services.prefs for
  # pref manipulation. This is the same context Marionette used.
  extensionApi = ''
    "use strict";

    const { ExtensionCommon } = ChromeUtils.importESModule(
      "resource://gre/modules/ExtensionCommon.sys.mjs"
    );

    this.themeToggle = class extends ExtensionCommon.ExtensionAPI {
      getAPI(context) {
        return {
          themeToggle: {
            async readMode(path) {
              try {
                const data = await IOUtils.readUTF8(path);
                return data.trim();
              } catch (e) {
                return "dark";
              }
            },
            async setColorScheme(mode) {
              const value = mode === "light" ? 1 : 0;
              Services.prefs.setIntPref(
                "layout.css.prefers-color-scheme.content-override",
                value
              );
              // Zen reads this pref for internal chrome styling like urlbar
              // text color. Without it, Zen's defaults override our CSS.
              Services.prefs.setIntPref(
                "zen.view.window.scheme",
                value
              );
            },
          },
        };
      }
    };
  '';

  # Background script polls the theme-mode file every 2 seconds via the
  # privileged Experiment API and sets the content-override pref on change.
  extensionBackground = ''
    let lastMode = null;

    async function checkMode() {
      try {
        const mode = await browser.themeToggle.readMode("${themeModeFile}");
        if (mode && mode !== lastMode) {
          await browser.themeToggle.setColorScheme(mode);
          lastMode = mode;
          console.log("[zen-theme-toggle] applied mode:", mode);
        }
      } catch (e) {
        console.error("[zen-theme-toggle] error:", e);
      }
    }

    console.log("[zen-theme-toggle] starting, watching:", "${themeModeFile}");
    checkMode();
    setInterval(checkMode, 2000);
  '';

  zenThemeExtension = let
    manifestFile = pkgs.writeText "manifest.json" extensionManifest;
    schemaFile = pkgs.writeText "schema.json" extensionSchema;
    apiFile = pkgs.writeText "api.js" extensionApi;
    backgroundFile = pkgs.writeText "background.js" extensionBackground;
  in
    pkgs.runCommand "zen-theme-toggle.xpi" {
      nativeBuildInputs = [pkgs.zip];
    } ''
      mkdir -p build
      cp ${manifestFile} build/manifest.json
      cp ${schemaFile} build/schema.json
      cp ${apiFile} build/api.js
      cp ${backgroundFile} build/background.js
      cd build
      zip -r $out manifest.json schema.json api.js background.js
    '';

  # CSS variable overrides for #main-window. Zen's theme engine sets
  # inline styles, so !important is required to win specificity.
  mkZenCssVars = p: ''
    --zen-main-browser-background: #${p.panelBg} !important;
    --zen-main-browser-background-toolbar: #${p.panelBg} !important;
    --zen-dialog-background: #${p.base00} !important;
    --tabpanel-background-color: #${p.panelBg} !important;
    --arrowpanel-background: #${p.panelBg} !important;
    --arrowpanel-color: #${p.base05} !important;
    --toolbox-textcolor: #${p.base05} !important;
    --zen-urlbar-background: #${p.base00} !important;
    --toolbar-field-color: #${p.base05} !important;
    --toolbar-field-focus-color: #${p.base05} !important;
  '';

  # Element-level color overrides. Chrome surfaces use panelBg to match
  # waybar, raised elements like the urlbar use base00.
  mkZenElementRules = p: ''
    #navigator-toolbox,
    #TabsToolbar,
    #PersonalToolbar,
    #sidebar-box,
    #sidebar {
      background-color: #${p.panelBg} !important;
      color: #${p.base05} !important;
    }

    .tabbrowser-tab .tab-label {
      color: #${p.base05} !important;
    }

    .urlbar-background {
      background-color: #${p.base00} !important;
    }

    #urlbar-input {
      color: #${p.base05} !important;
    }

    .panel-arrowcontent,
    panelview {
      background-color: #${p.panelBg} !important;
      color: #${p.base05} !important;
    }

    /* Toolbar icons and button labels inherit color via fill. */
    #navigator-toolbox toolbarbutton,
    #TabsToolbar toolbarbutton,
    .titlebar-button {
      color: #${p.base05} !important;
      fill: #${p.base05} !important;
    }

    .toolbarbutton-icon {
      fill: #${p.base05} !important;
    }

    /* Tab close button and other inline icons. */
    .tab-close-button,
    .tab-icon-image {
      fill: #${p.base05} !important;
    }

    /* Window title text. */
    .titlebar-text,
    #titlebar {
      color: #${p.base05} !important;
    }

    /* Workspace indicator in the sidebar. */
    .zen-current-workspace-indicator-name,
    .zen-workspace-icon {
      color: #${p.base05} !important;
    }
  '';

  # Dark theme is the default. Light variant activates via a -moz-pref
  # media query on content-override, which the extension sets to 1 for light
  # or 0 for dark at runtime.
  userChromeCss = ''
    #main-window {
      ${mkZenCssVars colorsDark}
    }
    ${mkZenElementRules colorsDark}

    @media -moz-pref('layout.css.prefers-color-scheme.content-override', 1) {
      #main-window {
        ${mkZenCssVars colorsLight}
      }
      ${mkZenElementRules colorsLight}
    }
  '';

  # Extension prefs: allow unsigned sideloaded extensions, enable experiment
  # APIs, and prevent auto-disabling. allow_transparent_browser must be off
  # to prevent the theme color from bleeding into website backgrounds.
  userJs = ''
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    user_pref("xpinstall.signatures.required", false);
    user_pref("extensions.experiments.enabled", true);
    user_pref("extensions.autoDisableScopes", 0);
    user_pref("browser.tabs.allow_transparent_browser", false);
  '';

  zenProfileDir = "$HOME/.var/app/app.zen_browser.zen/.zen";

  # Writes the desired mode to the theme-mode file inside the Flatpak
  # data directory. The WebExtension picks it up within 2 seconds.
  zenThemeSwitch = pkgs.writeShellApplication {
    name = "theme-switch-zen";
    text = ''
      mode="''${1:-dark}"
      echo "$mode" > "${zenProfileDir}/theme-mode"
    '';
  };
in {
  # Nix-managed theme source files. The activation script copies them into the
  # discovered Flatpak profile directory.
  xdg.configFile."zen/userChrome.css".text = userChromeCss;
  xdg.configFile."zen/user.js".text = userJs;

  # Register the Zen theme switcher so the global toggle updates web content.
  theme.toggle = [
    {
      name = "zen";
      switch = zenThemeSwitch;
    }
  ];

  # Seed userChrome.css, user.js, theme-mode, and extension into each Zen
  # profile on activation. Remove targets first since they may be read-only
  # nix store copies or symlinks.
  home.activation.seedZenTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    zen_base="${zenProfileDir}"
    [ -d "$zen_base" ] || exit 0

    profiles_ini="$zen_base/profiles.ini"
    [ -f "$profiles_ini" ] || exit 0

    # Seed theme-mode from the global mode file if not already present.
    if [ ! -f "$zen_base/theme-mode" ]; then
      mode=$(cat "$HOME/.config/theme-mode" 2>/dev/null || echo "dark")
      echo "$mode" > "$zen_base/theme-mode"
    fi

    while IFS='=' read -r key value; do
      [ "$key" = "Path" ] || continue
      profile_dir="$zen_base/$value"
      [ -d "$profile_dir" ] || continue

      chrome_dir="$profile_dir/chrome"
      mkdir -p "$chrome_dir"
      rm -f "$chrome_dir/userChrome.css"
      cp "${xdgConfig}/zen/userChrome.css" "$chrome_dir/userChrome.css"
      rm -f "$profile_dir/user.js"
      cp "${xdgConfig}/zen/user.js" "$profile_dir/user.js"

      # Install the theme toggle extension into the profile.
      ext_dir="$profile_dir/extensions"
      mkdir -p "$ext_dir"
      rm -f "$ext_dir/${extensionId}.xpi"
      cp "${zenThemeExtension}" "$ext_dir/${extensionId}.xpi"
    done < "$profiles_ini"
  '';
}
