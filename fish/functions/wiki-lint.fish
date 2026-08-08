function wiki-lint --description "Run wiki health checks"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set -l prompt (cat ~/.omp/agent/wiki/agents/wiki-lint.md | string collect)
    # omp -p is print mode: it needs a user message (the system prompt alone is
    # not enough). With no args the agent would silently exit, so default to the
    # structural-checks path; pass --with-contradictions to enable that check.
    if test (count $argv) -eq 0
        set argv "Run wiki health checks"
    end
    omp -p --no-session --no-extensions --model $model \
        --system-prompt "$prompt" \
        $argv
end
