# Feature Development: Behavioral Completeness

**Purpose:** Reduce important omissions in new features, especially when the product owner is unfamiliar with the underlying platform. Passing tests and clean code are necessary but do not establish feature completeness.

This is a lightweight process for Trial by Fyre projects. Apply it proportionally; do not turn small changes into paperwork.

Assign implementation and review roles per task rather than fixing roles to particular
products or models. Independent review means a separate reviewer with its own review
context: the implementer must not be the sole acceptance reviewer, and the author of
the proposed specification must not be its sole design reviewer. A different model
can provide an additional perspective but is not required.

Follow the repository's included collaboration and learning instructions for scope,
explanations, durable decision notes, and reporting. This process supplements those
instructions rather than duplicating them. If no such instructions exist, explain
significant choices and retain meaningful decisions proportionally to the task.


## 1. Classify the change

Before coding, assess the risk level and record a brief rationale in working notes or
the task checklist. Surface it to the product owner when it affects a decision,
required review, or process exception:

- **Low:** Copy, styling, or isolated adjustments with well-understood behavior and
  little consequence if incorrect. Implement and verify appropriately.
- **Medium:** New or changed behavior using familiar APIs and existing architecture,
  with bounded consequences. Write a short scenario checklist with expected results
  and verification plans; implement and review behavior afterward. Self-review is
  sufficient unless the change's risks call for independent review.
- **High:** Changes with material risk of data loss, incorrect access or payments,
  privacy/security failures, or significant lifecycle and recovery omissions; also
  unfamiliar platform behavior with consequential effects. Follow all stages below.

Payments, subscriptions, entitlements, persistence, migrations, background tasks,
notifications, external navigation, concurrency, and synchronization warrant careful
risk assessment. Merely touching one of these domains does not automatically make a
small, familiar change high risk. Evaluate the changed behavior and its consequences.
Elevate risk for cross-subsystem interactions, persistent user data changes, and
asynchronous or externally controlled state. The product owner can override classification;
record the reason and any omitted verification or review.

### Required stages by risk

| Risk | Discovery and specification | Design review | Verification and acceptance |
| --- | --- | --- | --- |
| Low | State intended change; no separate checklist required | As needed | Appropriate verification and brief results |
| Medium | Short scenario checklist with expected results and verification plans | As needed | Check scenarios and review behavior; report results and gaps |
| High | Authoritative research and behavior matrix | Independent review before high-risk implementation | Matrix coverage, independent behavioral review, and concise outcome summary |

Sections 2–6 specify the high-risk process. Apply their useful techniques to lower-risk
work proportionally; do not require a matrix or independent review for every change.

## 2. Discover behavior *before* coding (medium/high)

Start with the user's goal, not an API or implementation plan. The agent is responsible for finding relevant cases the product owner may not know to ask about.

For **high-risk** features:

1. Consult authoritative platform documentation for the relevant API, lifecycle, and constraints. Cite documentation links and distinguish verified facts from assumptions. If documentation cannot be checked, identify the affected assumption as unverified. Reporting the gap does not satisfy the research requirement. If it materially affects correctness or safety, resolve it before implementing dependent behavior, or obtain explicit agreement to proceed with a limited prototype.
2. Enumerate **states and transitions**, including initial, pending/unknown, success, change, cancellation, failure, recovery, and long-delayed return. Include app restart, offline behavior, multiple devices, and background/foreground transitions when applicable.
3. Examine interactions with existing features: data persistence, navigation, notifications, settings, accessibility, privacy, and UI state, as relevant.
4. Identify invariants (things that must always remain true) and what must never happen (e.g., silent data loss).
5. Separate **platform rules**, **product decisions**, and **unverified assumptions**. Ask the product owner to resolve product decisions; research platform rules instead of guessing.
6. Define what is explicitly **out of scope**.

Create a concise **behavior matrix** in working notes or an appropriate review artifact with: scenario/trigger, expected result, source or decision owner, and planned verification. Include both normal paths and important edge cases.

**Stop gate:** Do not implement high-risk behavior until material unresolved product decisions are answered. If the user explicitly wants a prototype, label assumptions and limitations.

## 3. Challenge the design independently (high)

Have a separate reviewer who did not author the specification or implement the feature review the behavior matrix **before coding**. Give the reviewer the product goal, current architecture, and relevant documentation, not merely the implementer's conclusion.

Reviewer prompt:

> Review this proposed feature for behavioral completeness, not code style. Identify missing states/transitions, platform lifecycle rules, failure/recovery paths, cross-feature interactions, user surprises, and unsupported assumptions. Look for scenarios a product owner unfamiliar with the framework would not know to ask about. Rank findings by severity; distinguish documented platform requirements from product choices. Do not invent requirements or propose unrelated features. State what evidence would resolve each finding.

Update the matrix and resolve significant findings. Agreement between agents is not proof of completeness.

If independent review is unavailable, report the gap and arrange a handoff rather than
substituting self-review. Continue research, specification, and other work that does
not depend on that review. Obtain explicit agreement before bypassing the high-risk
design review gate; record the exception and limitations. If acceptance review is
unavailable after implementation, report “implemented, independent review pending”
and keep full process completion pending.

## 4. Implement with traceable verification

- Implement the agreed behavior, not just the happy path.
- Associate each matrix row with an automated test, manual/sandbox test, or an explicit reason it cannot reasonably be tested.
- Cover state transitions and interactions, not only individual API methods.
- Use test doubles for deterministic failure and timing scenarios, and real platform/sandbox testing where mocks cannot validate integration.
- Apply the included collaboration and learning instructions when explaining choices and recording non-obvious architectural decisions.

## 5. Verify and challenge again

1. Run the relevant tests and report actual results, including known pre-existing failures.
2. Check every behavior-matrix row against code and verification evidence.
3. Ask an independent reviewer to examine the **implemented user behavior** and think through real-world release scenarios, including unexpected state changes, long-term use, and support requests.
4. Triage findings as **blocking**, **follow-up**, **accepted limitation**, or **not applicable**, with reasons. The product owner must approve material accepted limitations, consequential product tradeoffs, and deferral of blocking findings; agents must not silently downgrade these to follow-ups. Fix blocking issues and repeat targeted verification.
5. Confirm that documentation, user-facing language, and tests agree with the implementation.

## 6. Definition of done

Do not declare a high-risk feature complete solely because code builds or tests pass.
Maintain acceptance evidence in working notes or an appropriate review artifact covering:

- Intended behavior and key invariants
- Platform documentation reviewed (or gaps)
- Behavior-matrix coverage: automated, manual, and unverified
- Test results and environment
- Independent review findings and disposition
- Remaining assumptions, limitations, and risks
- Any product decisions still needed and review exceptions explicitly agreed by the product owner

Give the product owner a concise outcome summary following COLLABORATION.md (default
50–150 words). Summarize behavior, actual verification and independent review status;
surface material gaps, risks, decisions, and agreed review exceptions. Link supporting
evidence when useful rather than repeating the full acceptance record in chat. The
shorter report does not reduce any required research, matrix checks, tests, or review.

Material unresolved product decisions, blocking findings, or required reviews prevent
full process completion. Distinguish implementation status from acceptance status.

Use **“implemented, pending verification”** or **“implemented with known limitations”** when appropriate. Never imply exhaustive correctness.

## 7. Agent handoff template

> **Feature:** [goal from user's perspective]
>
> **Risk classification:** [low/medium/high, why]
>
> **Discovery:** Research relevant platform lifecycle and cross-feature interactions before coding. Surface scenarios I may not know to ask about. Distinguish platform rules, product choices, and assumptions.
>
> **Design:** For medium risk, produce a short scenario checklist with verification plans; for high risk, produce a behavior matrix. For high risk, obtain an independent adversarial design review before implementation. Stop for material product decisions.
>
> **Implementation:** Implement agreed behavior with verification linked to the checklist or matrix where required; use appropriate verification for low-risk work.
>
> **Acceptance:** Obtain independent behavioral review for high-risk work; report actual test results, gaps, and limitations. Do not call the feature complete just because tests pass.

## 8. Calibration examples

Project-specific retrospectives can help evaluate discovery without becoming universal
requirements. Keep them separate from this reusable process. For NextSeason, see
[the subscription calibration example](FEATURE_DEVELOPMENT_NEXTSEASON_CALIBRATION.md).
Include that companion file only where relevant, or replace this reference with an
appropriate example for another project.

## 9. Keep it lightweight

The behavior matrix can live in the task description or a short Markdown file; it need not become permanent documentation for every feature. Retain only meaningful decisions and constraints in the repository. Prefer a few high-value scenarios and explicit unknowns over a huge generic checklist. Revisit the process after a few features and remove steps that do not catch real problems.
