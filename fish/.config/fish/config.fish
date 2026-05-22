source /usr/share/cachyos-fish-config/cachyos-config.fish

# Hyprland IPC: terminals keep a stale HYPRLAND_INSTANCE_SIGNATURE after compositor restart.
if type -q hypr-sync-env
    function hypr_sync_env
        set -l sig (hypr-sync-env print 2>/dev/null)
        if test -n "$sig"
            set -gx HYPRLAND_INSTANCE_SIGNATURE $sig
        end
    end

    function hyprctl
        hypr_sync_env
        command hyprctl $argv
    end

    function hyprpm
        hypr_sync_env
        command hyprpm $argv
    end

    hypr_sync_env
end

# Disable the CachyOS fastfetch greeting on every new shell.
function fish_greeting
end
