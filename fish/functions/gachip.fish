function gachip
  git add .
  if test $argv[1]
    git commit -m "$argv[1]"
  else
    git commit -m "update"
  end
  git push origin HEAD
end
