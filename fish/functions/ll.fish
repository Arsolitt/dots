function ll --wraps=ls --wraps='exa -alg --icons --no-filesize --no-time -s name' --description 'alias ll exa -alg --icons --no-filesize --no-time -s name'
  exa -alg --icons --no-filesize --no-time -s name $argv
        
end
