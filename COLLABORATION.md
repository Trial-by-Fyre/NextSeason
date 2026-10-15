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
- After completing a task, follow the concise reporting guidance below.

## Testing Boundaries

- During implementation and review, run focused tests for the behavior being changed.
  Use the smallest relevant selection of tests or suites.
- The product owner controls full-suite testing before committing. Do not start a
  full-suite run unless the product owner explicitly requests it, even when a
  handoff or verification plan calls for one. Report that verification as pending;
  this boundary defers the run, not the verification requirement.
- Once relevant checks pass, repeat or broaden them only when subsequent changes,
  failures, or a specific unresolved concern justify it. Reuse existing results
  when they still apply to the current code.
- For an unexpected failure, briefly explain what failed and investigate within a
  bounded scope. If it remains unresolved, report the evidence and proposed next
  step before expanding into repeated reruns, baseline comparisons, unrelated
  fixes, or a broader testing cycle. Do not assume an intermittent failure is
  pre-existing merely because it passes when rerun.
- Keep test reports brief: what the run established, any remaining failures, and
  what verification is still pending. Do not repeat passing tests merely to seek
  additional reassurance.

## User-facing Reporting

- Default to a 50–150 word, outcome-focused completion summary; simple tasks may need
  less. Lead with what changed and its effect. Briefly summarize actual verification
  and review status, then surface material risks, gaps, decisions, or process exceptions.
  Omit sections that do not apply; do not add “none” sections to fill a template.
- Identify changed files concisely, grouping files that serve the same purpose. Include
  testing the project owner needs to do only when relevant.
- Keep progress updates brief and useful: meaningful findings, blockers, decisions, or
  changes of direction. Avoid routine step-by-step narration, repeated plans, and
  repeating reviewer reports or details already shared.
- Perform the full required analysis, edge-case checks, implementation, testing, and
  independent review. Keep detailed checklists, evidence, and review exchanges in
  working notes or appropriate review artifacts; link supporting detail when useful
  instead of copying it into chat. Retain only meaningful durable records.
- Brevity must not hide material risks, unresolved decisions, failed or unperformed
  checks, pending reviews, or agreed exceptions. Use more detail when necessary for
  an informed decision or when requested.
- Keep natural, conversational discussion when the project owner is exploring a topic.
  The completion-summary length is not a limit on those discussions.

## Coding Style

- Prefer simple, maintainable code. Optimize for readability over cleverness.
- Do not create unnecessary abstractions.
- Keep files under 500 lines when practical; use judgment rather than splitting code
  solely to meet a line count.
- Add comments for non-obvious logic.
- Preserve existing behavior except where the requested change intentionally alters it.
