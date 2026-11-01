function micns --description "Switch microphone noise suppression: PipeWire filter presets or the NPU denoiser"
    set -l conf_dir $HOME/.config/pipewire/pipewire.conf.d
    set -l conf $conf_dir/50-mic-denoise.conf
    set -l repo (path resolve (status dirname)/../..)/pipewire
    set -l unit npu-denoise.service
    set -l npu_src npu_mic
    set -l filter_src mic-denoise

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
        case npu off status
        case '*'
            echo "usage: micns [on|off|status|npu|deepfilter|rnnoise|rnnoise-max]" >&2
            return 2
    end

    set -l phys (pactl list short sources 2>/dev/null | awk '$2 ~ /^alsa_input/ {print $2; exit}')
    set -l unit_active 0
    systemctl --user is-active -q $unit; and set unit_active 1

    if test "$cmd" = npu
        if test -L $conf
            rm $conf
            systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
            systemctl --user restart pipewire pipewire-pulse wireplumber
            sleep 2
        end
        systemctl --user reset-failed $unit 2>/dev/null
        systemctl --user daemon-reload
        systemctl --user start $unit
        for attempt in (seq 40)
            pactl list short sources 2>/dev/null | string match -qr '^\d+\s+'$npu_src'(\s|$)'; and break
            sleep 0.25
        end
        if not pactl list short sources 2>/dev/null | string match -qr '^\d+\s+'$npu_src'(\s|$)'
            echo "micns: $unit did not expose $npu_src" >&2
            echo "micns: journalctl --user -u $unit" >&2
            return 1
        end
        pactl set-default-source $npu_src
        echo "micns: enabled (npu)"
        return 0
    end

    if test -n "$plugin"
        set -l src $repo/mic-denoise-$plugin.conf
        if not test -f $src
            echo "micns: unknown plugin '$plugin'" >&2
            return 1
        end
        if test -e $conf; and not test -L $conf
            echo "micns: $conf is not a dotfiles symlink — run dots/links.fish first" >&2
            return 1
        end
        if test $unit_active -eq 1
            systemctl --user stop $unit
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
        for attempt in (seq 40)
            pactl list short sources 2>/dev/null | string match -qr '^\d+\s+'$filter_src'(\s|$)'; and break
            sleep 0.25
        end
        if pactl list short sources 2>/dev/null | string match -qr '^\d+\s+'$filter_src'(\s|$)'
            for attempt in (seq 10)
                pactl set-default-source $filter_src >/dev/null 2>&1; and break
                sleep 0.2
            end
        else if test -n "$phys"
            pactl set-default-source $phys >/dev/null 2>&1
        end
        echo "micns: enabled ($plugin)"
        return 0
    end

    switch $cmd
        case off
            set -l changed 0
            if test $unit_active -eq 1
                systemctl --user stop $unit
                set changed 1
            end
            if test -L $conf
                rm $conf
                set changed 1
            end
            if test $changed -eq 0
                echo "micns: already disabled"
                return 0
            end
            systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
            systemctl --user restart pipewire pipewire-pulse wireplumber
            set -l ready ""
            for attempt in (seq 40)
                set ready (pactl list short sources 2>/dev/null | awk '$2 ~ /^alsa_input/ {print $2; exit}')
                test -n "$ready"; and break
                sleep 0.25
            end
            test -n "$ready"; and pactl set-default-source $ready >/dev/null 2>&1
            echo "micns: disabled"
        case status
            if test $unit_active -eq 1
                printf 'mode   : npu (%s)\n' $unit
                printf 'source : %s\n' (pactl get-default-source 2>/dev/null)
                return 0
            end
            if test -L $conf
                printf 'mode   : filter (%s)\n' (string replace -r '^mic-denoise-(.*)\.conf$' '$1' -- (path basename (path resolve $conf)))
            else
                printf 'mode   : off\n'
            end
            if pactl list short sources 2>/dev/null | string match -qr '^\d+\s+mic-denoise(\s|$)'
                printf 'filter : loaded\n'
            else
                printf 'filter : not loaded\n'
            end
            printf 'source : %s\n' (pactl get-default-source 2>/dev/null)
    end
end
