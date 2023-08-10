# see: https://github.com/nushell/nushell/blob/main/crates/nu-utils/src/sample_config/default_config.nu

def __dotfiles_find_up [filename: string, dir] {
    let candidate = ($dir | path join $filename)
    let parent_dir = ($dir | path dirname)
    if ($candidate | path exists) {
        $candidate
    } else if ($parent_dir != '/') and ($parent_dir | path exists) {
        __dotfiles_find_up $filename $parent_dir
    } else {
        null
    }
}

$env.config = {
    completions: {
        algorithm: 'fuzzy',
    },
    history: {
        file_format: 'sqlite',
        sync_on_enter: false, # prefer concurrent sessions to not share history
    },
    hooks: {
        env_change: {
            PWD: [
                {
                    code: { |before, after|
                        echo 'found .nvmrc'
                        # TODO: setup desired Node.js version
                    },
                    condition: { |before, after| not (__dotfiles_find_up '.nvmrc' $after | is-empty) },
                },
                # TODO: handle Python virtual environments
            ],
        },
    },
    show_banner: false,
}

source ~/.cache/starship/init.nu
use ~/.config/nushell/completions/git-completions.nu *
