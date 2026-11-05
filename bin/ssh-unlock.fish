#!/usr/bin/env fish

set -l keys $HOME/.ssh/main $HOME/.ssh/laptop
set -l ttl 7200
set -l failed 0

if not set -q SSH_AUTH_SOCK
    set -gx SSH_AUTH_SOCK /run/user/1000/ssh-agent.socket
end

if command -q fprintd-verify
    if not fprintd-verify >/dev/null 2>&1
        echo "ssh-unlock: fingerprint verification failed" >&2
        exit 1
    end
end

for key in $keys
    set -l name (path basename -- $key)
    set -l fingerprint (ssh-keygen -lf $key.pub 2>/dev/null | awk '{print $2}')

    if test -n "$fingerprint"; and ssh-add -l 2>/dev/null | string match -q -- "*$fingerprint*"
        echo "ssh-unlock: $name already loaded"
        continue
    end

    if set -l pass (secret-tool lookup service ssh key $name 2>/dev/null); and test -n "$pass"
        set -lx SSH_KEY_NAME $name
        set -lx SSH_ASKPASS $HOME/.local/bin/ssh-askpass-keyring
        set -lx SSH_ASKPASS_REQUIRE force
        ssh-add -t $ttl $key
        or set failed 1
    else
        echo "ssh-unlock: no keyring entry for $name, prompting for the passphrase"
        ssh-add -t $ttl $key
        or set failed 1
    end
end

if test $failed -ne 0
    exit 1
end
