function git-remote-to-https --description 'Switch a git remote URL from SSH to HTTPS'
    # usage: git-remote-to-https [remote]  (default: origin)
    set --local remote origin
    set --query argv[1]; and set remote $argv[1]

    # fail if not a repo / remote missing (git prints the error itself)
    set --local url (git remote get-url $remote); or return 1

    # ssh://git@host[:port]/path  ->  https://host/path
    # git@host:path (scp-like)    ->  https://host/path
    set --local new (string replace --regex '^ssh://[^/@]+@([^:/]+)(?::[0-9]+)?/' 'https://\1/' $url)
    set new (string replace --regex '^[^/@]+@([^:]+):' 'https://\1/' $new)

    if test "$new" = "$url"
        echo "git-remote-to-https: '$remote' is not an SSH url ($url)" >&2
        return 1
    end

    git remote set-url $remote $new
    and echo "$remote: $url -> $new"
end
