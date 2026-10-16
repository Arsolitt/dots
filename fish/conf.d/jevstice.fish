# jevstice.fish — TYPESAFE_API_KEY_COMMAND and the `jomp` alias for the omp jevstice extension
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

# The plugin is disabled in omp's plugin registry (~/.omp/plugins/omp-plugins.lock.json),
# so plain `omp` sessions load no addon. `jomp` opts in per session with an explicit -e
# path, which bypasses the disabled-plugin filter. If the plugin is ever reinstalled,
# the path stays stable; if it is uninstalled, `jomp` loses its target.
alias jomp 'omp -e ~/.omp/plugins/node_modules/jevstice/src/index.ts'
