function kgp --wraps='kubectl get pod' --description 'alias kgp kubectl get pod'
  kubectl get pod $argv
        
end
