if test -x $HOME/.local/bin/ssh-askpass-fprint
    set -gx SSH_ASKPASS $HOME/.local/bin/ssh-askpass-fprint
    set -gx SSH_ASKPASS_REQUIRE force
end
