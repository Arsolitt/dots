function wiki-ingest --description "Compile wiki sources into knowledge base"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set -l prompt (cat ~/.omp/agent/wiki/agents/wiki-compile.md | string collect)
    if test (count $argv) -eq 0
        set pending (wiki state pending)
        if test "$pending" = "nothing to ingest"
            echo $pending
            return 0
        end
        for source in $pending
            echo "ingesting: $source"
            omp -p --no-session --no-extensions --model $model \
                --system-prompt "$prompt" \
                "compile /home/arsolitt/Documents/obsidian/main/wiki/$source"
        end
    else
        omp -p --no-session --no-extensions --model $model \
            --system-prompt "$prompt" \
            "compile $argv[1]"
    end
end
