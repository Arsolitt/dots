function wiki-capture --description "Manual wiki flush for current or specified session"
    set model $WIKI_MODEL
    if test -z "$model"
        set model (wiki config model)
    end
    set session_id (opencode session list --format json 2>/dev/null | head -1 | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" 2>/dev/null)
    if test -n "$session_id"
        set tmp (mktemp --suffix=.json)
        opencode export $session_id > $tmp
        opencode run --agent wiki-flush --model $model "Transcript: $tmp\nSession: $session_id"
    else
        echo "no active session found"
        return 1
    end
end
