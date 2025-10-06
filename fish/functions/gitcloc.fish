function gitcloc --wraps='cloc 8c0b9ee' --wraps='cloc $(git log -1 --pretty=format:%h)' --description 'alias gitcloc cloc $(git log -1 --pretty=format:%h)'
  cloc $(git log -1 --pretty=format:%h) $argv
        
end
