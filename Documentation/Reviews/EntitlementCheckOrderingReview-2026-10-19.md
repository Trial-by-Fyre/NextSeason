# Entitlement check ordering — design and acceptance review

**Feature:** Prevent stale StoreKit entitlement reads from committing after newer reads, and ensure every `refreshEntitlements()` caller observes current access before it returns (purchase/restore/transaction finish contract).

**Risk:** High (subscriptions, entitlements, watchlist pause/resume).

**Status:** Implemented with a known limitation (accepted by the product owner 2026-10-19). Independent design and acceptance reviews: no blocking findings. Pending: full suite (owner-controlled), StoreKit sandbox/device verification.

## Process record

1. The first pass skipped the pre-implementation design review (subagent launch failed). That is a recorded process exception; later reviews do not erase it.
2. A serialized-chain design was implemented and reviewed. The acceptance review found that one stalled read blocked every later refresh, including purchase/update finishing, restore, and the update observer. The owner chose to replace it.
3. The replacement design was independently reviewed **before** implementation (2026-10-19). There were no blocking findings, and its recommendations were folded in.
4. Independent behavioral acceptance review of the implementation (2026-10-19): no blocking findings.

## Final ordering rule and caller contract

1. Each `refreshEntitlements()` request bumps `entitlementRefreshEpoch` and starts its own read in an unstructured main-actor task. Reads may overlap, so a stalled older read never blocks newer ones.
2. Only the read for the newest **request** may commit; superseded results are discarded. "Newest completed wins" was rejected because an older inactive answer could then pause rows while a newer purchase/restore read is pending.
3. Callers do not wait for their own read. They park in `entitlementCommitWaiters` and resume when the newest read commits. Purchase/update callers therefore see current access before the transaction finishes or simulation ends.
4. `entitlementWaiters` (initial resolution) stay separate. Complimentary grant and simulation resume only those, never refresh callers.
5. Caller cancellation never abandons a commit, because the read runs in the unstructured task.

**Invariants preserved:**
- Loading/unverified never pause rows.
- `.unverified` keeps the prior resolved state; on a first read it becomes `.unverified`.
- Complimentary and simulation rules are unchanged.
- A genuine lapse applies when the newest read says inactive.

## Platform facts and assumptions

- Apple documents `Transaction.currentEntitlements` as an async sequence of the latest entitling transactions (`Transaction.Transactions`, `Sendable`). No documented guarantee was found about ordering or snapshot timing for overlapping scans.
- **Unverified assumption:** a later-requested scan reflects state at least as new as an earlier one, including a just-delivered purchase. Only sandbox/device testing can reduce this.
- The original race was reproduced at app level with a controlled stub. It has not been shown with real StoreKit.

## Known limitation (accepted by product owner, 2026-10-19)

If the **newest** entitlement scan stalls, dependent operations wait until a later refresh succeeds or the app restarts. That includes the caller of that scan, any older superseded callers, and initial-resolution waiters on first launch. Two factors widen this:

- `handleSceneBecameActive` skips refreshing while the state is still `.loading`, so foregrounding does not retry a stalled first read.
- `Transaction.updates` handles one transaction at a time, so later updates queue behind a stalled handler.

No real StoreKit hang has been demonstrated; the limitation is accepted on that basis. Revisit if sandbox, device, or field reports show stalled scans.

## Review findings and disposition

1. Stalled-newest-read limit, including the two widening factors above: **accepted limitation** (product owner, 2026-10-19).
2. A background refresh caller parked across task expiration may later run `reconcile()`/`refreshAll` in a cancelled task (`AppCompositionRoot.swift` background handler): **follow-up**, not changed here.
3. Parked continuations and read tasks grow only with user-driven refreshes during a stall and clear on the next commit: **follow-up / low**.
4. The unreachable early-return check in `refreshEntitlements()`: **fixed** (removed; comment explains why no wakeup is lost).
5. Discard checks rely on a bounded `Task.yield()` settle rather than a commit counter: **follow-up**. The mutation check below shows they currently detect regressions.

## Verification

Focused tests in `PurchaseServiceEntitlementOrderingTests` (18):

- **Superseded results:** `supersededInactiveCannotRevokePlus`, `supersededActiveCannotRestoreStalePlus`, `supersededInactiveNeverPausesRows`, `waitersPendingUntilLatestCommit`, `cancelledLatestCallerDoesNotStrandWaiters`.
- **Transaction and simulation callers:** `transactionFinishWaitsForLatestRead`, `simulationEndsAfterLatestReadConfirmsPlus`, `supersededTransactionReadDelaysFinishUntilLatestCommit`, `supersededCallerFollowsReplacedTail`, `simulationEndsWhenUpdateReadIsSuperseded`.
- **Stalled reads:** `stalledOlderReadDoesNotBlockNewerCommit` (uses the SwiftData repository and checks for no double finish), `stalledNewestReadParksCallersUntilLaterCommit` (documents the limit), `burstOfRefreshesResumesAllCallers`.
- **Restore, verification failure, complimentary:** `restoreOverlappingHeldLifecycleRead`, `newestUnverifiedKeepsConfirmedPlus`, `newestUnverifiedFromLoadingIsUnverified`, `complimentaryGrantDuringHeldRead`, `supersededUnverifiedPreservesConfirmedPlusInSwiftData`.

Results (2026-10-19, iPhone 16 simulator): 18/18 ordering tests pass. `PurchaseServiceTests` and `SubscriptionDowngradeTests` also pass (72 total with the ordering tests). The full suite was not run.

Mutation check: with the newest-request guard disabled, 16 of 18 ordering tests fail. The two that pass don't depend on that guard (complimentary grant; superseded `.unverified`). Earlier mutation checks on the serialized design also showed the superseded-caller tests failing without the caller-completion wait.

## Remaining manual verification

- StoreKit sandbox: purchase, Ask to Buy approval, and restore while a foreground entitlement refresh is in flight.
- Physical device deferred investigation unchanged.
