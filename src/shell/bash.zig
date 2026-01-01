// bash shell integration for zprompt

pub const bash_init_script =
    \\# zprompt bash init script
    \\# Add to ~/.bashrc: eval "$(zprompt init bash)"
    \\
    \\__zprompt_timer_start() {
    \\    __zprompt_start_time="${__zprompt_start_time:-$EPOCHREALTIME}"
    \\}
    \\
    \\__zprompt_timer_stop() {
    \\    local exit_status=$?
    \\    local duration=0
    \\
    \\    if [[ -n "$__zprompt_start_time" ]]; then
    \\        local end_time="$EPOCHREALTIME"
    \\        # EPOCHREALTIME is in seconds with fractional part
    \\        # Convert to milliseconds
    \\        local start_ms=$(printf "%.0f" "$(echo "$__zprompt_start_time * 1000" | bc 2>/dev/null || echo 0)")
    \\        local end_ms=$(printf "%.0f" "$(echo "$end_time * 1000" | bc 2>/dev/null || echo 0)")
    \\        duration=$((end_ms - start_ms))
    \\        [[ $duration -lt 0 ]] && duration=0
    \\    fi
    \\    unset __zprompt_start_time
    \\
    \\    PS1="$(zprompt prompt --status "$exit_status" --cmd-duration "$duration")"
    \\}
    \\
    \\# Use DEBUG trap for preexec-like behavior
    \\trap '__zprompt_timer_start' DEBUG
    \\
    \\# Use PROMPT_COMMAND for precmd-like behavior
    \\PROMPT_COMMAND="__zprompt_timer_stop${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    \\
    \\# Initial prompt
    \\PS1="$(zprompt prompt --status 0 --cmd-duration 0)"
    \\
;
