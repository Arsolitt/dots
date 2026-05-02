function cc --description "Launch Claude Code with preferred defaults"
    argparse 'y/yolo' 'm/model=' 'z/zai' 'l/long' -- $argv
    or return

    set -lx CLAUDE_CODE_NO_FLICKER 1
    set -lx CLAUDE_CODE_NEW_INIT 1
    set -lx CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING 1
    set -lx CLAUDE_CODE_INVESTIGATE_FIRST 1
    set -lx CLAUDE_CODE_ALWAYS_ENABLE_EFFORT 1
    set -lx CLAUDE_CODE_SUBAGENT_MODEL claude-sonnet-4-6

    if set --query _flag_zai
        set -l zai_token (pass zai/api-key 2>/dev/null)
        if test -z "$zai_token"
            echo "cc: failed to retrieve ZAI API key from pass" >&2
            return 1
        end
        set -fx ANTHROPIC_AUTH_TOKEN $zai_token
        set -fx ANTHROPIC_BASE_URL http://127.0.0.1:8889
        set -fx API_TIMEOUT_MS 30000000
    end

    set -l model
    if test -n "$_flag_model"
        set model $_flag_model
    else if set --query _flag_zai
        set model glm-5.1
        
    else
        set model claude-opus-4-6
    end

    # Normalize: strip [1m] suffix so classification works regardless of how model was passed
    set -l base_model (string replace --regex '\[1m\]$' '' -- $model)

    set -l effort
    set -l force_long
    switch $base_model
        case 'claude-opus-4-6'
            set effort max
            set force_long 1
        case 'claude-opus-4-7'
            set effort xhigh
            set force_long 1
        case 'glm-*'
            set effort max
    end

    if set --query _flag_long; or test -n "$force_long"
        set model $base_model"[1m]"
    else
        set model $base_model
    end

    if set --query _flag_zai
        set -lx CLAUDE_CODE_SUBAGENT_MODEL $base_model
    end

    set --local cmd claude --model $model --exclude-dynamic-system-prompt-sections
    if test -n "$effort"
        set --append cmd --effort $effort
    end

    if set --query _flag_yolo
        set --append cmd --dangerously-skip-permissions
    end

    $cmd $argv
end
