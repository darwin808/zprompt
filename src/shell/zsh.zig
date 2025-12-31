// zsh shell integration for zprompt

pub const zsh_init_script =
    \\# zprompt zsh init script
    \\# Add to ~/.zshrc: eval "$(zprompt init zsh)"
    \\
    \\zprompt_preexec() {
    \\    ZPROMPT_START_TIME=$((EPOCHREALTIME * 1000))
    \\}
    \\
    \\zprompt_precmd() {
    \\    local exit_status=$?
    \\    local duration=0
    \\
    \\    if [[ -n "$ZPROMPT_START_TIME" ]]; then
    \\        local end_time=$((EPOCHREALTIME * 1000))
    \\        duration=$((end_time - ZPROMPT_START_TIME))
    \\        unset ZPROMPT_START_TIME
    \\    fi
    \\
    \\    PROMPT="$(zprompt prompt --status $exit_status --cmd-duration $duration)"
    \\}
    \\
    \\# Set up hooks
    \\autoload -Uz add-zsh-hook
    \\add-zsh-hook preexec zprompt_preexec
    \\add-zsh-hook precmd zprompt_precmd
    \\
    \\# Initial prompt
    \\PROMPT="$(zprompt prompt --status 0 --cmd-duration 0)"
    \\
;
