# Completions for "kc" alias (kubectl kc)
function __kc_complete
    set -l tokens (commandline -opc)
    set -l current (commandline -ct)
    # Replace "kc" with empty to get subcommand args
    set -e tokens[1]
    # Call kubectl kc __complete with the current args
    kubectl kc __complete $tokens $current 2>/dev/null | string match -rv '^:.*'
end

complete --command kc --no-files --arguments '(__kc_complete)'
