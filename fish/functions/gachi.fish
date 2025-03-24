function gachi
  git add .
  if test $argv[1]
    git commit -m "$argv[1]"
  else
    git commit -m "WIP"
  end
end
