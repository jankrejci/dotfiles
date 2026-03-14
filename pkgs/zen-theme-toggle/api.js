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
