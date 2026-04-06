function fish_prompt
    set -l display_path (string replace -r '^'$HOME '' '~' $PWD)
    echo -n (set_color cccccc)
    printf '%s' $display_path
    echo -n (set_color normal) ' $ '
end
