function cc --description "Launch Claude Code with preferred defaults"
    argparse 'y/yolo' 'm/model=' -- $argv
    or return

    set -lx CLAUDE_CODE_NO_FLICKER 1
    set -lx CLAUDE_CODE_NEW_INIT 1

    set --local model $_flag_model
    if test -z "$model"
        set model claude-opus-4-7
    end

    set --local cmd claude --effort max --model $model

    if set --query _flag_yolo
        set --append cmd --dangerously-skip-permissions
    end

    $cmd $argv
end
