function kknd --wraps="k delete pod --field-selector 'status.phase!=Running' -A --force" --wraps="kubectl delete pod --field-selector 'status.phase!=Running' -A --force" --description "alias kknd=kubectl delete pod --field-selector 'status.phase!=Running' -A --force"
    kubectl delete pod --field-selector 'status.phase!=Running' -A --force $argv
end
