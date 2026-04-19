function cc --description "Launch Claude Code with preferred defaults"
    argparse 'y/yolo' 'm/model=' 'z/zai' -- $argv
    or return

    set -lx CLAUDE_CODE_NO_FLICKER 1
    set -lx CLAUDE_CODE_NEW_INIT 1

    if set --query _flag_zai
        if test -z "$ZAI_API_KEY"
            echo "cc: ZAI_API_KEY is not set" >&2
            return 1
        end
        set -fx ANTHROPIC_AUTH_TOKEN $ZAI_API_KEY
        set -fx ANTHROPIC_BASE_URL http://127.0.0.1:8889
        set -fx API_TIMEOUT_MS 3000000
    end

    set --local cmd claude --effort max

    if test -n "$_flag_model"
        set --append cmd --model $_flag_model
    else if set --query _flag_zai
        set --append cmd --model glm-5-turbo
    else
        set --append cmd --model claude-opus-4-7
    end

    if set --query _flag_yolo
        set --append cmd --dangerously-skip-permissions
    end

    $cmd $argv
end
