function wiki-ask --description "Query the personal wiki"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set -l prompt (cat ~/.omp/agent/wiki/agents/wiki-query.md | string collect)
    omp -p --no-session --no-extensions --model $model \
        --system-prompt "$prompt" \
        $argv
end
