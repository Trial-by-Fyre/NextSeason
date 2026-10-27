# Recent discussion suggestions — October 26, 2026

## Scope and limits

Reviewed accessible NextSeason product/testing/development chats for October 12–26, 2026, including older turns in the feature-area, R13, R15–R17, and post-R17 review chats. Adjacent October 11 subscription/consolidation context and the recent app-marketing discussion were checked where relevant. Compared proposals with the current Product Evolution, App Store Readiness and Monetization roadmaps, review dispositions, follow-up notes, and current testing documents.

This is a suggestion-recovery audit, not a new code review, feature approval, release decision, or test pass. Source chat titles and links below identify the discussions actually inspected. Some ChatGPT assistant replies were exposed only as content-reference placeholders, so their full wording could not be recovered; readable user quotations and the related Codex handoffs provide the available evidence. No claim is made to have recovered inaccessible Claude/Xcode chats, deleted conversations, or every unsaved remark.

Risk: low documentation-only capture. Existing plans and accepted limitations remain in effect. Suggestions are not implementation commitments. Before implementing a technical follow-up, verify whether subsequent code changes have already resolved it.

## Previously missing from repository planning records

| ID | Suggestion | Status and intended boundary | Source |
|---|---|---|---|
| S-01 | Tap a paused Watchlist row to open the Plus paywall. | Product proposal captured under Watchlist Management. Consider success/restore leading to the selected show’s detail once access is active, and cancellation leaving the user on Watchlist. Those navigation details were recommended in review; they still need product confirmation/design before implementation. Existing regression tests correctly expect no paused detail access under current behavior. No v1.0 commitment inferred. | October 23: [Conversation start](https://chatgpt.com/c/6ada9400-fe7c-83e8-8db1-dd02c9bb6ddc), user’s paused-row question; [Review NextSeason release readiness](codex://threads/01a16ac4-4f88-73f2-b403-a629ac5f991a), missing tap flow and proposed acceptance case. |
| S-02 | Show a Free-tier usage indicator, e.g. “Tracking N of 3 free shows.” | Product idea captured for evaluation, separately from the already-recorded collapsed-header count proposal. Count active shows even in collapsed sections; paused shows consume no active slot. Evaluate whether this provides enough value without adding clutter. Not an approved design. | October 22: [Watchlist UI Suggestion Review](https://chatgpt.com/c/6ada8a42-ba70-83e8-ac13-39151f772e2e); [Add deferred Watchlist usability](codex://threads/01a165af-fe47-7b53-8a5d-c8e25a9387d8) explicitly allowed recording it as a separate optional idea, but the saved edit recorded only header-count visibility. |
| S-03 | Represent Search failure/retry eligibility with a structured error kind rather than comparing localized message text. | Low-priority maintainability suggestion captured under Continuous Improvement. Preserve the existing distinction: local mapping bootstrap failure requires restart; ordinary recoverable errors offer Try Again. Current `SearchViewModel.isSearchRetryAvailable` still compares against `localMappingUnavailableMessage`. No user-visible defect or release blocker established by that comparison alone. | October 18: [Review code by feature area](codex://threads/01a1318e-6124-7df2-95a3-5674b07a59f3), assessment of the mapping Retry correction (“an explicit error type would be sturdier later”). |

## Additional suggestion recalled by the owner

**S-04 — About color consistency, especially Dark Mode.** The owner recalled prior feedback that About’s colors feel randomly assigned. The earlier audit did not capture it, and a targeted repository/available-chat-text search did not locate a specific durable entry; general appearance/accessibility checks do not capture this design concern. Added to Product Evolution → Continuous Improvement from the owner’s clarification in the current **Review StoreKit test script** chat on October 26, 2026. Review the hierarchy and consistency of text, icon, link, and status colors in both appearances while preserving contrast and accessible distinctions. This is a design-review proposal, not a confirmed accessibility defect or an approved palette. The original discussion’s date/location remains unverified.

## Correctness concern recovered from chat — not optional polish

**C-01: blocked Add Show retry may toggle a reactivated show off.** The October 23 [Review NextSeason release readiness](codex://threads/01a16ac4-4f88-73f2-b403-a629ac5f991a) flagged a timing-unverified concern: Search/Show Detail check tracked state, then schedule a task that later calls a toggle. Reactivation or another add between those steps could turn the retry into removal. An idempotent add was suggested as a possible correction, not implemented or proven necessary in that review.

Current code still has the pre-task guard plus later toggle in both views. That confirms the shape of the concern, not an actual reproduced race. The focused StoreKit pass 7B already checks for unintended removal/duplicates/Undo during reactivation; this note now makes the investigation and suggested approach explicit. Keep the issue **open for targeted verification**, rather than silently accepting it as a future cosmetic improvement or claiming it is fixed. Priority and release disposition require evidence and an owner decision. No code or tests were changed during this audit.

## Already recorded elsewhere — retain existing disposition

These ideas were not lost, but some are hard to discover from the future roadmap. The roadmap now links to this index rather than duplicating their requirements.

| Topic discussed | Existing durable record | Current interpretation |
|---|---|---|
| Make collapsed Watchlist counts clearer; shorten the oversized notification-disabled banner | Product Evolution Roadmap → Watchlist Management / Continuous Improvement | Already recorded as deferred usability work. |
| Let users choose which three shows remain active after Plus expires | Product Evolution Roadmap → Subscription downgrade improvements | Already recorded future product work. |
| Export/import restoration; monitoring summary; update history; CloudKit/server monitoring and notification enhancements | Product Evolution Roadmap | Already recorded. The monitoring summary is related to, but does not specifically describe, S-02’s Free capacity indicator. |
| Future update history must distinguish “update recorded” from “accepted for scheduling”; neither proves an alert was seen; enabling notifications must not replay history | [Approved feature-area analysis](2026-10-12-feature-area-review-analysis.md), R03 design and decisions | Already recorded product requirements; the history feature itself is already in the roadmap. |
| Include Ignore Complimentary Plus state explicitly in Copy/Share diagnostics rather than relying only on breadcrumbs | [Override review](IgnoreComplimentaryPlus-2026-10-21.md), implementation-review dispositions | Already recorded follow-up. Mentioned again in [Testing script prompts 1 2 3](https://chatgpt.com/c/6ad93a84-e7f4-83e8-9115-3eb9c63a574b); not a newly missing idea. |
| Cancelled background caller may reconcile late; growth of waiters during a stall; replace bounded yields with explicit synchronization | [Entitlement ordering review](EntitlementCheckOrderingReview-2026-10-19.md), findings/disposition | Already recorded technical follow-ups. Accepted stalled-newest-read limitation remains distinct. |
| Notification navigation can cancel a Search-detail removal; obsolete resolve alerts; superseded profiling outcome; retry UI/integration gaps; weak Dynamic Type visibility assertions | [October 19 follow-ups](2026-10-19-follow-ups.md) | Already tracked with priorities and decision/verification distinctions. No rescheduling here. |
| Episode-1 pointer churn can reverse an undated display status; verify persisted repeated-notification behavior if revisited | [R09 follow-up](2026-10-18-r09-pointer-churn-follow-up.md) | Already recorded; no new evidence or policy decision in this audit. |
| Mapping DB reopening/live per-hit fallback; stronger mapping durability; repository dateAdded contract; catalog-load coalescing; transient store-open retry | [Feature-area review](2026-10-12-feature-area-review.md), [analysis](2026-10-12-feature-area-review-analysis.md), and [Review NextSeason defects after R17](codex://threads/01a15168-8cf7-7662-9aed-e7a62df93c60) | Existing review proposals/deferrals, not newly approved roadmap commitments. Original review also contains fixes subsequently completed; recheck current code before selecting any item. |
| Broader accessibility coverage for About, paywall, tips, recovery and permission flows; real-device gaps and title clipping | [Feature-area review](2026-10-12-feature-area-review.md), [known failures](Known-Test-Failures.md), and current beta/StoreKit scripts | Recorded issue/verification work, not new app-feature requests. |
| Physical-device launch-loop/profiling investigation and missing trace evidence | [Profiling investigation](2026-10-16-profiling-investigation.md) and App Store Readiness Roadmap | Already recorded; remains subject to the owner’s explicit deferral. |

### Alternatives discussed, not selected

The October 22 Watchlist discussion also compared auto-expanding collapsed sections and listing the kept shows in the pause alert. They were alternatives to the usage/count ideas, not approved enhancements. Preserve the existing roadmap direction **not to auto-expand sections**. Listing kept shows may be reconsidered if useful, but no separate commitment is inferred from the comparison.

## Source coverage

Relevant chats inspected, with their source-provided titles:

- [Conversation start](https://chatgpt.com/c/6ada9400-fe7c-83e8-8db1-dd02c9bb6ddc) and [Review NextSeason release readiness](codex://threads/01a16ac4-4f88-73f2-b403-a629ac5f991a).
- [Watchlist UI Suggestion Review](https://chatgpt.com/c/6ada8a42-ba70-83e8-ac13-39151f772e2e) and [Add deferred Watchlist usability](codex://threads/01a165af-fe47-7b53-8a5d-c8e25a9387d8).
- [Testing script prompts 1 2 3](https://chatgpt.com/c/6ad93a84-e7f4-83e8-9115-3eb9c63a574b), [Review NextSeason changes](codex://threads/01a16582-74e3-76f1-ac3c-e34e9fa43f9d), and [Review StoreKit release readiness](codex://threads/01a16035-faf8-7332-b4cf-f9a2f525cf9b).
- [TestFlight Troubleshooting](https://chatgpt.com/c/6ad7c12d-d3dc-83e8-9340-5851f174fd79), [Review NextSeason Prompt 2 changes](codex://threads/01a16012-55ab-7c13-9291-a231334ffee0), and [Review NextSeason testing fixes](codex://threads/01a15ce9-df78-7df1-8d25-c2e4d59971eb).
- [Review NextSeason Defects](https://chatgpt.com/c/6ad55916-6404-83e8-863b-99032326b588), [Review NextSeason defects after R17](codex://threads/01a15168-8cf7-7662-9aed-e7a62df93c60), and all available turns of [Review code by feature area](codex://threads/01a1318e-6124-7df2-95a3-5674b07a59f3).
- [Review R13 watchlist changes](codex://threads/01a13c57-e85e-7972-81de-448c719a938e), [Review R05 search race fix](codex://threads/01a140f3-c65f-7b13-828f-7627a0fda4df), [Review R15–R17 fixes](codex://threads/01a14187-1ee4-7c01-bd77-40a2f1085c65), [Fix iOS 18 accessibility audit tests](codex://threads/01a12e60-33b1-7fc1-930d-fc5773dc617d), and [Run tests on an iOS 18 simulator](codex://threads/01a12d75-4928-7bd2-9b68-a22decd73a61).
- Adjacent context: [Review NextSeason subscription gaps](codex://threads/01a129a1-5ada-7c70-a650-8c58c5c5d8d3) (most recent turns) and [Consolidate StoreKit test scripts](codex://threads/01a12d61-3135-78b1-8e25-8b58e55dd0d3). These establish prior test/roadmap context, not new October 12–26 ideas.
- [Brainstorm app marketing ideas](https://chatgpt.com/c/6acfb3ec-b2c4-83e8-a0c3-13298f031d4a): community participation/peer advice discussion, not an app-feature proposal. No marketing memberships, schedules, or purchases were created from it.

The available Codex archive listing was empty; the ChatGPT archive listing contained no recent NextSeason discussion. Unrelated personal chats were excluded. The current manual-test conversation is available directly in this task and its review dispositions are already saved separately.
