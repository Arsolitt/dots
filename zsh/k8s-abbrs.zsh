# k8s-abbrs.zsh — kubectl context abbreviations (zsh-abbr).
# Ported from fish/functions/kc*.fish. These were fish functions but are
# abbreviations in zsh — they expand inline, showing the full context switch
# before Enter, which is better UX than a silent function.

abbr -S kcg="kubectl config use-context arsolitt@gateway"
abbr -S kch="kubectl config use-context arsolitt@home"
abbr -S kclpp="kubectl config use-context arsolitt@lp-prod"
abbr -S kcocp="kubectl config use-context arsolitt@ock-prod"
abbr -S kcpld="kubectl config use-context arsolitt@psclp-dev"
abbr -S kcpli="kubectl config use-context arsolitt@psclp-infra"
abbr -S kcpsp="kubectl config use-context arsolitt@psc-prod"
