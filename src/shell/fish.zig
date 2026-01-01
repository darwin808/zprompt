// fish shell integration for zprompt

pub const fish_init_script =
    \\# zprompt fish init script
    \\# Add to ~/.config/fish/config.fish: zprompt init fish | source
    \\
    \\function fish_prompt
    \\    set -l exit_status $status
    \\    set -l duration $CMD_DURATION
    \\
    \\    # CMD_DURATION is in milliseconds in fish
    \\    if test -z "$duration"
    \\        set duration 0
    \\    end
    \\
    \\    zprompt prompt --status $exit_status --cmd-duration $duration
    \\end
    \\
    \\# Disable the default fish_mode_prompt (vi mode indicator)
    \\function fish_mode_prompt
    \\end
    \\
;
