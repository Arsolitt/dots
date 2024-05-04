function kl --wraps='kubectl logs' --description 'alias kl kubectl logs'
  kubectl logs $argv
        
end
