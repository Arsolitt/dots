function cat --wraps=bat --wraps='bat --plain' --wraps='bat --plain --paging=never' --wraps='bat --paging=never' --wraps='bat testconfig --style plain --paging never' --wraps='bat --style plain --paging never' --description 'alias cat bat --style plain --paging never'
  bat --style plain --paging never $argv
        
end
