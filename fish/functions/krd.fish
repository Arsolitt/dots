function krd --wraps='kubectl rollout restart ds' --description 'alias krd kubectl rollout restart ds'
  kubectl rollout restart ds $argv
        
end
