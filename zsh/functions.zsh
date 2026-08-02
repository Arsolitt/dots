# functions.zsh — complex fish functions + dynamic git commands.
# Ported 1:1 from fish/functions/*.fish. No new functionality.

# ─── Git branch helpers (used by dynamic git functions) ─────
git_current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null
}

git_default_branch() {
  git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null \
    | sed 's@^origin/@@' || echo main
}

# ─── Dynamic git commands (were abbrs with __git.current/default_branch) ──
# zsh-abbr expansions are static, so these need function bodies for runtime
# branch resolution. Each passes "$@" for additional arguments.

ggsup()  { git branch --set-upstream-to="origin/$(git_current_branch)" "$@"; }
gfm()    { git fetch origin "$(git_default_branch)" --prune && git merge FETCH_HEAD; }
ggl()    { git pull origin "$(git_current_branch)" "$@"; }
glom()   { git log --oneline --decorate --color "$(git_default_branch)".. "$@"; }
gmom()   { git merge "origin/$(git_default_branch)" "$@"; }
ggp()    { git push origin "$(git_current_branch)" "$@"; }
ggp!()   { git push origin "$(git_current_branch)" --force-with-lease "$@"; }
gpu()    { git push origin "$(git_current_branch)" --set-upstream "$@"; }
ggpnp()  { git pull origin "$(git_current_branch)" && git push origin "$(git_current_branch)"; }
grbm()   { git rebase "$(git_default_branch)" "$@"; }
grbmi()  { git rebase "$(git_default_branch)" --interactive "$@"; }
grbmia() { git rebase "$(git_default_branch)" --interactive --autosquash "$@"; }
grbom()  { git fetch origin "$(git_default_branch)" && git rebase FETCH_HEAD; }
grbomi() { git fetch origin "$(git_default_branch)" && git rebase FETCH_HEAD --interactive; }
grbomia() { git fetch origin "$(git_default_branch)" && git rebase FETCH_HEAD --interactive --autosquash; }
ggu()    { git pull --rebase origin "$(git_current_branch)" "$@"; }
gcom()   { git checkout "$(git_default_branch)" "$@"; }
gmr()    { git push origin "$(git_current_branch)" --set-upstream -o merge_request.create "$@"; }
gmwps()  { git push origin "$(git_current_branch)" --set-upstream -o merge_request.create -o merge_request.merge_when_pipeline_succeeds "$@"; }

# ─── Git functions ──────────────────────────────────────────

gachi() {
  git add .
  if [[ -n $1 ]]; then
    git commit -m "$1"
  else
    git commit -m "WIP"
  fi
}

gachip() {
  git add .
  if [[ -n $1 ]]; then
    git commit -m "$1" --no-verify
  else
    git commit -m "WIP" --no-verify
  fi
  git push origin HEAD
}

gbage() {
  git for-each-ref --sort=committerdate refs/heads/ \
    --format="%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))"
}

gbda() {
  git branch --merged | \
    command grep -vE '^\*|^[[:space:]]*(master|main|develop)[[:space:]]*$' | \
    command xargs -r -n 1 git branch -d

  local default_branch
  default_branch=$(git_default_branch)
  git for-each-ref refs/heads/ "--format=%(refname:short)" | \
    while read -r branch; do
      local merge_base
      merge_base=$(git merge-base "$default_branch" "$branch")
      if [[ $(git cherry "$default_branch" "$(git commit-tree "$(git rev-parse "${branch}^{tree}")" -p "$merge_base" -m _)") == -* ]]; then
        git branch -D "$branch"
      fi
    done
}

gdv() {
  git diff -w "$@" | view -
}

gignored() {
  git ls-files -v | grep '^[[:lower:]]' "$@"
}

gitcloc() {
  cloc "$(git log -1 --pretty=format:%h)" "$@"
}

gloor() {
  git log --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short --reverse "$@"
}

glp() {
  [[ -n $1 ]] && git log --pretty="$1"
}

grename() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: $0 old_branch new_branch"
    return 1
  fi
  git branch -m "$1" "$2"
  git push origin :"$1" && git push --set-upstream origin "$2"
}

grt() {
  cd "$(git rev-parse --show-toplevel || echo .)"
}

gtest() {
  git stash push -q --keep-index --include-untracked || return
  command "$@"
  local cmdstatus=$?
  git reset -q
  git restore .
  git stash pop -q --index || return $?
  return $cmdstatus
}

gtl() {
  git tag --sort=-v:refname -n -l "$1"*
}

gwip() {
  git add -A
  git rm "${(@f)$(git ls-files --deleted)}" 2>/dev/null
  git commit -m "--wip--" --no-verify
}

gunwip() {
  git log -n 1 | grep -qc -e '--wip--' && git reset HEAD~1
}

# ─── Kubernetes functions ───────────────────────────────────

kknd() {
  kubectl delete pod --field-selector 'status.phase!=Running' -A --force "$@"
}

kkndt() {
  kubectl get pods --all-namespaces \
    | grep Terminating \
    | awk '{print $2, "-n", $1}' \
    | xargs -L1 kubectl delete pod --grace-period=0 --force "$@"
}

linstor() {
  kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor "$@"
}

# ─── Utility functions ──────────────────────────────────────

crs() {
  cursor "$@" &>/dev/null &!
}

eswa() {
  local mime=$(wl-paste --list-types 2>/dev/null | grep -E '^image/' | head -1)
  if [[ -z $mime ]]; then
    echo "Error: No image in clipboard" >&2
    return 1
  fi
  wl-paste -t "$mime" | satty -f - -o - --actions-on-escape=save-to-file,exit
}

# ─── Wiki CLI wrappers ──────────────────────────────────────

wiki() {
  ~/.omp/agent/wiki/bin/wiki "$@"
}

wiki-ask() {
  local model="$WIKI_MODEL"
  if [[ -z $model ]]; then
    model=$(wiki config model)
  fi
  local prompt="$(cat ~/.omp/agent/wiki/agents/wiki-query.md)"
  omp -p --no-session --no-extensions --model "$model" \
    --system-prompt "$prompt" \
    "$@"
}

wiki-ingest() {
  local model="$WIKI_MODEL"
  if [[ -z $model ]]; then
    model=$(wiki config model)
  fi
  local prompt="$(cat ~/.omp/agent/wiki/agents/wiki-compile.md)"
  if [[ $# -eq 0 ]]; then
    local pending
    pending=("${(@f)$(wiki state pending)}")
    if [[ $pending == "nothing to ingest" ]]; then
      echo "$pending"
      return 0
    fi
    for source in $pending; do
      echo "ingesting: $source"
      omp -p --no-session --no-extensions --model "$model" \
        --system-prompt "$prompt" \
        "compile /home/arsolitt/Documents/obsidian/main/wiki/$source"
    done
  else
    omp -p --no-session --no-extensions --model "$model" \
      --system-prompt "$prompt" \
      "compile $1"
  fi
}

wiki-lint() {
  local model="$WIKI_MODEL"
  if [[ -z $model ]]; then
    model=$(wiki config model)
  fi
  local prompt="$(cat ~/.omp/agent/wiki/agents/wiki-lint.md)"
  omp -p --no-session --no-extensions --model "$model" \
    --system-prompt "$prompt" \
    "$@"
}
