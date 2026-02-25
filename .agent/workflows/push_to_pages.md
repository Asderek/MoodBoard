---
description: Commits all current changes and pushes them to GitHub to deploy to Pages
---

# Push to Pages
Use this workflow when the user explicitly asks to push, commit, or deploy the current changes to GitHub Pages.

1. Check the git status to see what files were modified.
2. Formulate a concise and accurate commit message summarizing all changes made.
// turbo
3. Run `git add .` to stage all changes.
// turbo
4. Run `git commit -m "[commit message]"` to commit the changes.
// turbo
5. Run `git push` to push to the remote repository.

If there are any errors during the push, attempt `git pull --rebase` and then try `git push` again.
