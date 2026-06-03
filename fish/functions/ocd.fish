function ocd --description "OpenCode with wiki auto-capture on exit"
    set --local cwd (pwd)
    set --local resume_id ""

    # Extract session ID from -s/--session flags
    set --local i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case -s --session
                set i (math $i + 1)
                if test $i -le (count $argv)
                    set resume_id $argv[$i]
                end
            case '--session=*'
                set resume_id (string replace --regex '^--session=' '' $argv[$i])
        end
        set i (math $i + 1)
    end

    if test -n "$resume_id"
        command opencode $argv
        set --local exit_code $status
        nohup wiki flush $resume_id $cwd >/dev/null 2>&1 &
        disown
        return $exit_code
    end

    # New session: diff before/after to find the right one
    set --local before (opencode session list --format json 2>/dev/null)
    command opencode $argv
    set --local exit_code $status
    set --local after (opencode session list --format json 2>/dev/null)
    set --local session_id (python3 -c "
import json, sys
try:
    before_ids = set()
    if sys.argv[1]:
        before_ids = set(s['id'] for s in json.loads(sys.argv[1]))
    after = json.loads(sys.argv[2]) if sys.argv[2] else []
    cwd = sys.argv[3]
    for s in after:
        if s['id'] not in before_ids and s.get('directory') == cwd:
            print(s['id'])
            break
except Exception:
    pass
" "$before" "$after" "$cwd" 2>/dev/null)

    if test -n "$session_id"
        nohup wiki flush $session_id $cwd >/dev/null 2>&1 &
        disown
    end

    return $exit_code
end
