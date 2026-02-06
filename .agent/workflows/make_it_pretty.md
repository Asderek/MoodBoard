---
description: Cleanup code (remove prints, fix warnings) and update documentation/tasks. Trigger with "let's make it pretty".
---

1. **Remove Debug Prints**:
   - Search for `print(` statement in all `.gd` scripts.
   - Remove temporary debug prints (e.g. `print("clicked")`, `print(variable)`).
   - Keep essential Error/Warning prints (e.g. `print("Error: ...")`).

2. **Fix Warnings**:
   - Check open files or key scripts (`Main.gd`, `UI.gd`, `MoodNode.gd`, `MainMenu.gd`) for common warnings.
   - Rename unused arguments with `_` prefix (e.g. `func _on_signal(_arg)`).
   - Remove unused variables.
   - Fix shadowed variables.

3. **Update Documentation (`README.md`)**:
   - Ensure the "Features" or "Controls" section includes the latest implemented features.
   - Verify instructions are up to date.

4. **Update Task List (`task.md`)**:
   - detailed check of `task.md`.
   - Mark completed tasks as `[x]`.
   - Ensure no inconsistent states (e.g. subtasks done but parent not).

5. **Final Polish**:
   - Verify code formatting (indentation) if obvious issues exist.
   - Notify user that the project is clean and ready.

6. **Generate Commit Summary**:
   - Compile a list of all changes made in the current session (features, fixes, refactors).
   - Format it as a "Commit Message" or "Changelog" for the user to review.
