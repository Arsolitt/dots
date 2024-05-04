function ka --wraps='kubectl apply -f' --description 'alias ka kubectl apply -f'
  kubectl apply -f $argv
        
end
