function gachip
  git add .
  if test $argv[1]
    git commit -m "$argv[1]" --no-verify
  else
    git commit -m "WIP" --no-verify
  end
  git push origin HEAD
end
