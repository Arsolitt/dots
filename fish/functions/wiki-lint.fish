function wiki-lint --description "Run wiki health checks"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    opencode run --agent wiki-lint --model $model $argv
end
