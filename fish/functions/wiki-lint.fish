function wiki-lint --description "Run wiki health checks"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set -l prompt (cat ~/.omp/agent/wiki/agents/wiki-lint.md | string collect)
    omp -p --no-session --no-extensions --model $model \
        --system-prompt "$prompt" \
        $argv
end
