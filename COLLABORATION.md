# Collaboration Preferences

- Never commit changes. Leave all changes uncommitted in the working copy so the
  project owner can review and commit them.
- Before editing, briefly explain the intended change. Prefer small, reviewable diffs.
- Keep changes tightly scoped to the requested task. Do not perform unrelated cleanup,
  refactoring, renaming, modernization, or style changes.
- Do not reformat existing files unless formatting is explicitly part of the task.
- Preserve existing structure, conventions, and formatting unless there is a specific
  reason to change them. Do not change the app architecture unless explicitly requested.
- Do not delete code unless it is clearly unused or the task requests its removal.
- Preserve transcripts, conversation history, and historical/archive files. They record
  what happened and must remain unchanged.
- Keep documentation changes limited to those needed to accurately describe the requested
  change. Report broader documentation work separately. Do not revise roadmap or planning
  decisions unless the task explicitly requests it.
- Report advisable changes outside the requested scope instead of making them.
- Do not introduce third-party dependencies without asking first.
- Do not treat placeholder, mock, test, or historical values as authoritative configuration.
  If a required real value or other essential information is missing, or uncertainty prevents
  safe completion, stop and ask rather than guessing.
- After completing a task, report exactly which files changed and briefly explain why each
  changed. Summarize validation performed and any testing the project owner should do.

## Coding Style

- Prefer simple, maintainable code. Optimize for readability over cleverness.
- Do not create unnecessary abstractions.
- Keep files under 500 lines when practical; use judgment rather than splitting code
  solely to meet a line count.
- Add comments for non-obvious logic.
- Preserve existing behavior except where the requested change intentionally alters it.
