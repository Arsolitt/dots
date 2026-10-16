# jevstice.fish — TYPESAFE_API_KEY_COMMAND for the omp jevstice extension
#
# The TypeSafe API key stays in the OS keyring; jevstice resolves it by running this
# command and trimming stdout. Restore after key rotation:
#   Linux: secret-tool store --label="TypeSafe API key (jevstice)" service typesafe account api-key
#   macOS: security add-generic-password -s typesafe -a api-key -w

if test (uname) = Darwin
    set -gx TYPESAFE_API_KEY_COMMAND "security find-generic-password -s typesafe -a api-key -w"
else if type -q secret-tool
    set -gx TYPESAFE_API_KEY_COMMAND "secret-tool lookup service typesafe account api-key"
end
