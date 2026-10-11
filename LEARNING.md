# Development and Learning

AI-assisted development in this project should optimize for both shipping high-quality
software and helping the project owner retain an understanding of the codebase.

When making changes:

- Routine boilerplate, familiar patterns, and easily referenced API syntax can be
  implemented without extensive explanation.

- Before introducing a significant new concept, architectural pattern, framework, or
  unfamiliar Swift technique, explain what problem it solves, why it is appropriate
  here, and any important alternatives or tradeoffs.

- For significant app-specific logic or architecture, explain the reasoning behind the
  implementation, not merely what the code does.

- Distinguish between:
  1. Concepts and design decisions that should be understood and retained.
  2. Syntax or API details that can reasonably be looked up when needed.
  3. Language and platform knowledge that a senior engineer may reasonably be expected to recall
     during an interview.

- Explicitly flag items in the third category as useful interview knowledge.

- Do not quiz the project owner on concepts that have not first been explained. After a
  significant change, a brief teach-back may be useful, but focus on the concept rather
  than exact syntax.

- For non-obvious architectural decisions, unusual workarounds, or constraints that a
  future maintainer might question, leave an appropriate durable explanation in the
  repository, such as documentation, a decision-log entry, or a concise code comment.

Keep this lightweight. Do not turn routine development into a tutorial or slow down
straightforward work unnecessarily.
