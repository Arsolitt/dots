function wiki-ask --description "Query the personal wiki"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set prompt ~/.omp/agent/wiki/agents/wiki-query.md
    omp -p --no-session --no-extensions --model $model \
        --system-prompt (cat $prompt) \
        $argv
end
