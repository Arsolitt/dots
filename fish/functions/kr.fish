function kr --wraps='kubectl rollout restart deployment' --description 'alias kr kubectl rollout restart deployment'
  kubectl rollout restart deployment $argv
        
end
