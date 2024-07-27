function uhc --wraps='docker-compose run --rm' --wraps='docker-compose -f ./.docker/docker-compose.yml run --rm' --description 'alias uhc docker-compose -f ./.docker/docker-compose.yml run --rm'
  docker-compose -f ./.docker/docker-compose.yml run --rm $argv
        
end
