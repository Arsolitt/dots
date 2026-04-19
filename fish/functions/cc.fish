function cc --description "Launch Claude Code with preferred defaults"
    argparse 'y/yolo' 'm/model=' 'z/zai' 'l/long' -- $argv
    or return

    set -lx CLAUDE_CODE_NO_FLICKER 1
    set -lx CLAUDE_CODE_NEW_INIT 1
    set -lx CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING 1

    if set --query _flag_zai
        set -l zai_token (pass zai/api-key 2>/dev/null)
        if test -z "$zai_token"
            echo "cc: failed to retrieve ZAI API key from pass" >&2
            return 1
        end
        set -fx ANTHROPIC_AUTH_TOKEN $zai_token
        set -fx ANTHROPIC_BASE_URL http://127.0.0.1:8889
        set -fx API_TIMEOUT_MS 3000000
    end

    set -l model
    if test -n "$_flag_model"
        set model $_flag_model
    else if set --query _flag_zai
        set model glm-5-turbo
    else
        set model claude-opus-4-6
    end

    if set --query _flag_long
        set model $model"[1m]"
    end

    set --local cmd claude --effort max --model $model

    if set --query _flag_yolo
        set --append cmd --dangerously-skip-permissions
    end

    $cmd $argv
end
