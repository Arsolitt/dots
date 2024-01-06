function gachi
git add .
if test "$msg"
git commit -m "$msg"
else
git commit -m "update"
end
git push origin HEAD
end
