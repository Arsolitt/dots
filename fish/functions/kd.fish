function kd --wraps='kubectl delete -f' --description 'alias kd kubectl delete -f'
  kubectl delete -f $argv
        
end
