function uhc --wraps='docker-compose run --rm' --description 'alias uhc docker-compose run --rm'
  docker-compose run --rm $argv
        
end
