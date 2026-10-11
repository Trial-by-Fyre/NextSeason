# Calibration Example: NextSeason Subscriptions

<!--
Historical context: the following records how work was assigned previously.
It does not prescribe assignments for future tasks.
-->

<!--
Default AI role assignments (Trial by Fyre / NextSeason)

| Agent | Primary responsibility |
| --- | --- |
| ChatGPT | Product architecture, domain research, specifications, coordination, acceptance review |
| Claude | Implementation and testing |
| Codex | Independent design and implementation reviews |
| Product owner (you) | Product decisions and final acceptance |

These are defaults, not rigid assignments. If Codex implements a feature,
Claude should independently review it (and vice versa). An agent must not be
its own sole reviewer. ChatGPT helps coordinate but is not an independent
reviewer of specifications it authored. Actual delegation between tools may
require Work or explicit handoffs; this comment does not automate orchestration.
-->

Use this as a calibration case for the process, **not** as a claim that every issue is still present in the current codebase.

| Scenario the discovery phase should have surfaced | Why it matters | Expected discovery mechanism |
| --- | --- | --- |
| Cancellation versus actual expiration | Cancellation need not mean immediate loss of paid access | Subscription state-transition inventory |
| Expiration with more than three tracked shows | Free-tier limit interacts with existing user data | Cross-feature matrix + product decision |
| Restoration of previously paused shows on renewed access | Recovery must be defined, not just downgrade | Reversible state transitions |
| Billing problems, revocation, and temporary uncertainty | Entitlement state can change or be unresolved | Platform lifecycle research |
| Cold launch from a notification before entitlement resolution | Navigation can race asynchronous access checks | Cross-feature review + timing tests |
| Offline launch and delayed entitlement information | Unknown state is not automatically Free or Plus | Failure/recovery inventory |
| Changes while the app remains open | State cannot be checked only at purchase time | Transition inventory |
| Cross-device purchase/restore | Access must reflect platform account state | Integration research and sandbox verification |

**Calibration test:** For the next high-risk feature, check whether discovery produces comparably important scenarios *before* coding. If it misses obvious cases, improve the process rather than simply adding more tests afterward.
