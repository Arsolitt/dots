function oc --description "OpenCode with wiki auto-capture on exit"
    set --local cwd (pwd)
    command opencode $argv
    set --local exit_code $status

    set --local session_json (opencode session list --max-count 1 --format json 2>/dev/null)
    if test -z "$session_json"
        return $exit_code
    end

    set --local session_id (echo $session_json | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d[0]['id'] if d else '')" 2>/dev/null)
    if test -z "$session_id"
        return $exit_code
    end

    nohup wiki flush $session_id $cwd >/dev/null 2>&1 &
    disown

    return $exit_code
end
