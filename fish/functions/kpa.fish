function kpa --wraps='kubectl get po -A' --description 'alias kpa kubectl get po -A'
  kubectl get po -A $argv
        
end
