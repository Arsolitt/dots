function kgs --wraps='kubectl get svc -A' --description 'alias kgs kubectl get svc -A'
  kubectl get svc -A $argv
        
end
