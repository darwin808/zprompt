// powershell shell integration for zprompt

pub const powershell_init_script =
    \\# zprompt PowerShell init script
    \\# Add to $PROFILE: Invoke-Expression (&zprompt init powershell)
    \\
    \\$global:__zprompt_start_time = $null
    \\
    \\function global:__zprompt_preexec {
    \\    $global:__zprompt_start_time = [System.Diagnostics.Stopwatch]::StartNew()
    \\}
    \\
    \\function global:prompt {
    \\    $exit_status = 0
    \\    if (-not $?) {
    \\        $exit_status = 1
    \\    }
    \\    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    \\        $exit_status = $LASTEXITCODE
    \\    }
    \\
    \\    $duration = 0
    \\    if ($global:__zprompt_start_time -ne $null) {
    \\        $global:__zprompt_start_time.Stop()
    \\        $duration = [int]$global:__zprompt_start_time.ElapsedMilliseconds
    \\        $global:__zprompt_start_time = $null
    \\    }
    \\
    \\    $prompt_output = zprompt prompt --status $exit_status --cmd-duration $duration
    \\    $prompt_output
    \\}
    \\
    \\# Hook into PSReadLine if available for preexec behavior
    \\if (Get-Module -ListAvailable PSReadLine) {
    \\    Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
    \\        __zprompt_preexec
    \\        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    \\    }
    \\}
    \\
;
