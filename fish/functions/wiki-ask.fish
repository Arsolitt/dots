function wiki-ask --description "Query the personal wiki"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    opencode run --agent wiki-query --model $model $argv
end
