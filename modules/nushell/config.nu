# see: https://github.com/nushell/nushell/blob/main/crates/nu-utils/src/sample_config/default_config.nu

$env.config = {
    completions: {
        algorithm: 'fuzzy',
    },
    history: {
        file_format: 'sqlite',
        sync_on_enter: true,
        isolation: true,
    },
    show_banner: false,
    keybindings: [
      {
        name: open_editor
        modifier: control
        keycode: char_e
        mode: [vi_normal vi_insert emacs]
        event: { send: OpenEditor}
      }
    ]
}

source ~/.cache/starship/init.nu
source ~/.cache/zoxide/init.nu
source ~/.cache/broot/init.nu
source ~/.cache/carapace/init.nu
