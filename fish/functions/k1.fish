function k1 --wraps='kubectl describe' --description 'alias k1 kubectl describe'
  kubectl describe $argv
        
end
