function krs --wraps='kubectl rollout restart sts' --description 'alias krs kubectl rollout restart sts'
  kubectl rollout restart sts $argv
        
end
