function wiki-ingest --description "Compile wiki sources into knowledge base"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    if test (count $argv) -eq 0
        set pending (wiki state pending)
        if test "$pending" = "nothing to ingest"
            echo $pending
            return 0
        end
        for source in $pending
            echo "ingesting: $source"
            opencode run --agent wiki-compile --model $model "compile /home/arsolitt/Documents/obsidian/main/wiki/$source"
        end
    else
        opencode run --agent wiki-compile --model $model "compile $argv[1]"
    end
end
