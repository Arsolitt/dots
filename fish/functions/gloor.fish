function gloor --wraps=git\ log\ --pretty=format:\'\%C\(yellow\)\%h\ \%Cred\%ad\ \%Cblue\%an\%Cgreen\%d\ \%Creset\%s\'\ --date=short\ --reverse --description alias\ gloor=git\ log\ --pretty=format:\'\%C\(yellow\)\%h\ \%Cred\%ad\ \%Cblue\%an\%Cgreen\%d\ \%Creset\%s\'\ --date=short\ --reverse
  git log --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short --reverse $argv
        
end
