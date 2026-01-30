function kkndt --wraps='kubectl get pods --all-namespaces | grep Terminating | awk \'{print $2, "-n", $1}\' | xargs -L1 kubectl delete pod --grace-period=0 --force' --description 'alias kkndt=kubectl get pods --all-namespaces | grep Terminating | awk \'{print $2, "-n", $1}\' | xargs -L1 kubectl delete pod --grace-period=0 --force'
    kubectl get pods --all-namespaces | grep Terminating | awk '{print $2, "-n", $1}' | xargs -L1 kubectl delete pod --grace-period=0 --force $argv
end
