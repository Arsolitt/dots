# aliases.zsh — simple fish wrappers ported to zsh aliases.
# Ported from fish/functions/*.fish. These were fish functions that behaved
# as pure aliases with argument passthrough; zsh aliases pass args natively.

# ─── kubectl ────────────────────────────────────────────────
alias k='kubectl'
alias k1='kubectl describe'
alias ka='kubectl apply -f'
alias kd='kubectl delete -f'
alias ke='kubectl exec -it'
alias kg='kubectl get'
alias kgp='kubectl get pod'
alias kgs='kubectl get svc -A'
alias kl='kubectl logs'
alias kpa='kubectl get po -A'
alias kr='kubectl rollout restart deployment'
alias krd='kubectl rollout restart ds'
alias krs='kubectl rollout restart sts'

# ─── flux ───────────────────────────────────────────────────
alias fgk='flux get kustomizations'
alias fgsg='flux get sources git'

# ─── guarded: only apply if underlying binary exists ─────────
(( $+commands[bat] ))            && alias cat='bat --style plain --paging never'
(( $+commands[eza] ))            && alias exa='eza'
(( $+commands[code] ))           && alias code='code -n'
(( $+commands[make] ))           && alias make='make -s'
(( $+commands[backblaze-b2] ))   && alias bb='backblaze-b2'

# ─── ll (was exa wrapper, inlined to eza) ────────────────────
alias ll='eza -alg --icons --no-filesize --no-time -s name'
