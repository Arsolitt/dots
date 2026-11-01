function micns --description "Toggle microphone noise suppression (PipeWire smart filter)"
    set -l conf_dir $HOME/.config/pipewire/pipewire.conf.d
    set -l conf $conf_dir/50-mic-denoise.conf
    set -l repo (path resolve (status dirname)/../..)/pipewire

    set -l cmd status
    test (count $argv) -gt 0; and set cmd $argv[1]

    set -l plugin
    switch $cmd
        case on
            if test -L $conf
                set plugin (string replace -r '^mic-denoise-(.*)\.conf$' '$1' -- (path basename (path resolve $conf)))
            else
                set plugin rnnoise
            end
        case deepfilter rnnoise rnnoise-max
            set plugin $cmd
        case off status
        case '*'
            echo "usage: micns [on|off|status|deepfilter|rnnoise|rnnoise-max]" >&2
            return 2
    end

    if test -n "$plugin"
        set -l src "$repo/mic-denoise-$plugin.conf"
        if not test -f "$src"
            echo "micns: unknown plugin '$plugin'" >&2
            return 1
        end
        if test -e $conf; and not test -L $conf
            echo "micns: $conf is not a dotfiles symlink — run dots/links.fish first" >&2
            return 1
        end
        set -l current
        test -L $conf; and set current (path resolve $conf)
        if test "$current" = (path resolve $src)
            echo "micns: already enabled ($plugin)"
            return 0
        end
        mkdir -p $conf_dir
        ln -sfn $src $conf
        if not test -e $conf
            echo "micns: failed to link $conf -> $src" >&2
            return 1
        end
        systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
        systemctl --user restart pipewire pipewire-pulse wireplumber
        echo "micns: enabled ($plugin)"
        return 0
    end

    switch $cmd
        case off
            if not test -L $conf
                echo "micns: already disabled"
                return 0
            end
            rm $conf
            systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
            systemctl --user restart pipewire pipewire-pulse wireplumber
            echo "micns: disabled"
        case status
            if test -L $conf
                printf 'config : enabled (%s)\n' (string replace -r '^mic-denoise-(.*)\.conf$' '$1' -- (path basename (path resolve $conf)))
            else
                printf 'config : disabled\n'
            end
            if wpctl status 2>/dev/null | string match -q '*mic-denoise*'
                printf 'filter : loaded\n'
            else
                printf 'filter : not loaded\n'
            end
            printf 'source : %s\n' (pactl get-default-source 2>/dev/null)
    end
end
