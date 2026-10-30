# Xcode pending subscription consistency guard

**October 30, 2026. The Claude-review follow-up is implemented and independently reviewed. The owner passed the requested updated-candidate checks: fresh 4C and normal Xcode purchase/simulation completion. History-sensitive purchases, approval while closed and decline remain separate verification items.**

## Evidence and scope

[Transaction #6](StoreKitPendingTransaction6-2026-10-30.md) appears in verified current entitlements while the owner reports Pending Approval. Its subscription status changes from unknown raw `0` to subscribed `1` only after approval; IDs and purchase/expiration dates stay the same. No immediate approval update was observed after the previous code had already finished its premature update. The post-approval relaunch recovers the entitlement by reading current entitlements.

Risk is **high**: changing access and transaction completion can grant unpaid access or block a legitimate subscriber. Authoritative sources reviewed: [current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements), [subscription status](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status-swift.property), [Ask to Buy testing](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode), [transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates), [unfinished transactions](https://developer.apple.com/documentation/storekit/transaction/unfinished), and [finish](https://developer.apple.com/documentation/storekit/transaction/finish()). Apple documents current entitlements as the active/grace subscription source and finish as acknowledging delivery.

Independent design review rejected a generic second-status requirement: if that query failed at cold launch, an otherwise verified paid entitlement could lose access. The accepted design applies the consistency guard **only to Plus transactions whose environment is Xcode**. App Store/sandbox entitlement policy, offline behavior, consumable tips, and architecture remain unchanged; they bypass the extra query and deferred queue. No production exposure or universal meaning for raw `0` is inferred.

## Implemented behavior

- Local Xcode Plus current entitlements must correlate to a verified subscription status transaction and renewal payload. Subscribed/grace permits access; known expired/revoked/billing retry does not. Unknown, missing, mismatched, failed, or unverified status is `.unverified`, never a new grant or a confirmed lapse. An independently valid Plus entitlement still wins the overall scan. Existing confirmed access survives uncertainty under the existing service policy.
- Correlation requires the same original ID and either the same transaction ID or a strictly newer purchase date in that lineage. Older, unrelated, and equal-date/different-ID statuses cannot authorize the candidate. This is a conservative resolution rule for the local test environment, not a general ordering claim for all subscription changes.
- Unknown local updates receive no application callback, processed-ID insertion, or finish. A direct raw success that cannot resolve its local subscription state throws the existing purchase-verification error, rather than reporting success. Known terminal updates still process and finish so reconciliation works.
- A small in-memory delivery queue retries at startup, foreground return, and successful restore, outside entitlement refresh callbacks to avoid recursion. It also rechecks unresolved local candidates every two seconds while an observer exists, so approval can recover without another event or user action. Generation checks prevent work from an old observation delivering after stop/restart. Entry tokens and validation claims coordinate retries with observer delivery. Stopping observation clears only transient candidates; unresolved StoreKit transactions remain unfinished for later launch.
- No pending denial, purchase state, show identity, or abandoned Add Show callback is persisted. The original add remains process-local and is not reconstructed after relaunch.

The new Xcode status query is awaited even without the diagnostic launch argument. A stalled local query can delay local entitlement resolution or delivery. Production and sandbox transactions never await this new dependency. The existing debug argument controls logging only. Automatic retries add no background execution assertion; the OS may suspend the process or briefly permit it to run after backgrounding. The task releases its queue reference across each sleep and stops when the queue drains or observation stops.

## Behavior matrix and verification

| Scenario | Expected result | Verification |
|---|---|---|
| Pending, relaunch, status 0 | No Plus grant; no add | Policy unit test; new manual 4C pending |
| Unknown update, repeated uncertainty | No process/finish | Delivery unit test |
| Same-ID approval, subscribed | Deliver then finish once | Policy/delivery unit tests; first live attempt failed as recorded below; revised candidate pending |
| Approval without another event or lifecycle action | Restore Plus before finishing | Service-wired automatic-retry test; revised live acceptance pending |
| Approval while closed | Launch restores Plus; N untracked | Manual pending |
| Decline before/after relaunch | No Plus, success, or add | Unknown-state policy; actual decline manual 4D pending |
| Subscribed / grace | Local access permitted without naive date cutoff | Policy tests |
| Expired / revoked / billing retry | No local entitlement; terminal delivery allowed | Policy/delivery tests |
| Other valid access plus uncertain candidate | Valid entitlement still wins | Policy status precedence and unchanged aggregate scan; real-platform scenario pending |
| Empty/error/unverified/future/mismatched status | Uncertain, no false grant or confirmed revoke | Policy tests; existing service entitlement tests |
| Overlapping retries / observer | One queued candidate processed once | Controlled suspension tests |
| Stop/restart while validation suspended | No late delivery; new candidate survives | Controlled suspension tests |
| Startup / foreground / restore | Retry outside refresh recursion | Service lifecycle test |
| Production / sandbox | Zero extra status lookups | Bypass unit test and adapter review |
| Tips, simulation, overlapping entitlement refresh | Existing behavior retained | Focused existing suites |

## Review and results

The independent reviewer approved the narrowed design before implementation, requiring generation checks after status suspension and atomic candidate claiming. Independent behavioral review found no blocking code findings. It confirmed the environment bypass, no callback/finish for uncertain local transactions, lifecycle recovery, generation checks and candidate claims. This queue claims a queued candidate once; ordinary StoreKit duplicate deliveries retain the existing service deduplication behavior.

The focused Xcode 27.0 / iOS 27.0 simulator run passed **65 tests in five suites**: `XcodeSubscriptionValidationTests`, `StoreTransactionDeliveryTests`, `PurchaseServiceTests`, `PurchaseServiceEntitlementOrderingTests`, and `FreeTierSimulationTests`. Result bundle: `/private/tmp/NextSeasonPendingValidation.xcresult`. This also compiled the app and test targets. After the final explicit queue-snapshot refinement, all **6 delivery tests** passed again (`/private/tmp/NextSeasonPendingDeliveryFinal.xcresult`). `git diff --check` passed. No manual StoreKit scenario was performed by the agent, and no owner transaction was modified. No full-suite run was requested.

Manual acceptance must use a **new pending request**, since #6 was already finished by the earlier implementation. Preserve #6 evidence before resetting local test state. Required live checks: pending relaunch stays limited; live approval after guarded relaunch unlocks; approval while closed restores; decline never succeeds; legitimate existing access survives another pending request; abandoned N stays untracked. If approval produces no update, foreground return should retry the deferred candidate; needing that recovery does not satisfy the expected immediate live-approval check. Do not close 4C until its original assertions pass on the candidate.


## Live approval follow-up: missing active recovery

The owner reran the first guarded candidate: access stayed limited after relaunch, but approving the purchase while NextSeason stayed running did not unlock Plus. Xcode showed the transaction as unfinished. This confirms improvement in preventing the premature grant and failure of live approval recovery; **4C remains failed**.

[Read-only simulator logs](Attachments/StoreKit-7-Guarded-Relaunch-2026-10-30.txt) show the latest pending request as transaction 7, returning pending at 13:26:21 America/Los_Angeles. After relaunch at 13:26:46 it appears in the entitlement and update streams with status 0; no application transaction-update callback follows in the captured interval. The owner did not separately supply this attempt's transaction ID or approval timestamp, so the log does not independently timestamp the approval. No owner transaction was modified by the agent.

The unfinished warning is expected while the candidate is uncertain. It must clear after approved content has been delivered. The first candidate depended on another transaction event or a startup/foreground/restore trigger; none of those is guaranteed to run merely because the manager's approval state changes while the app stays active. Lifecycle-only recovery was therefore insufficient for this scenario.

The revised candidate adds a single sequential retry loop to the local-only deferred queue. It sleeps two seconds between checks, freshly validates every candidate, and never treats elapsed time as approval. A resolved candidate processes through the existing observer, waits for application processing, then finishes. Cancellation and generation checks after sleep and after validation prevent old work or cleanup from affecting replacement observation. The task stops on drain/stop and releases the queue across sleep; no persistent pending state is introduced. Production/sandbox and tips still bypass the queue entirely.

Independent design and implementation review found no blocking issues with this revision. It required weak retention across sleep, generation-safe cleanup, and a test proving actual service access before finish when approval arrives without an event. Added deterministic tests cover an unknown retry followed by silent approval, stop during sleep, generation replacement, and queue release during the second sleep. Existing overlapping retry/observer and status-policy tests remain relevant. The revised candidate compiled and passed **17 focused tests in two suites** (`StoreTransactionDeliveryTests` and `XcodeSubscriptionValidationTests`) on the separate iOS 27.0 simulator with Xcode 27.0. Result bundle: `/private/tmp/NextSeasonSilentApproval.xcresult`. The earlier 65-test purchase/service/simulation run remains applicable to unchanged code. `git diff --check` passed; no full suite was run. Live StoreKit acceptance remains pending.

An unresolved or declined local candidate can continue checking until its state resolves or observation stops. Disappearance/timeout must never be treated as approval. Decline behavior remains a manual verification item; no production availability policy is changed by this local fallback.

For the revised manual check, rebuild/run `SKTesting`. The already approved unfinished transaction should restore access and finish on launch; preserve its evidence before a fresh reset. Then repeat 4C with a new pending request: relaunch stays limited, approval while active restores Plus after a fresh two-second check, the unfinished warning clears, and N stays untracked. The check may take longer if the status query itself is slow. No pass is claimed until the live sequence is verified.


## Approved relaunch follow-up: access restored, completion still missing

The owner rebuilt and ran the automatic-retry candidate: Plus restored, but the manager's unfinished warning remained. [Read-only launch logs](Attachments/StoreKit-7-Access-Without-Finish-2026-10-30.txt) show transaction 7 in current entitlements with subscribed state 1 at 13:40:22 and 13:40:23 America/Los_Angeles. The captured launch has no transaction-update delivery. This explains access without a finish call: reading entitlements restores access independently, but the transient recovery queue had no update event from which to rebuild its candidates after process death. Live approval and finish acceptance remain open.

The next candidate explicitly reads [Transaction.unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished) during the existing startup/foreground/successful-restore recovery hooks. The scan is enabled only after a verified Xcode Plus transaction is observed in that process. Each result is filtered for verification, Xcode environment and Plus product, then routed through the same status guard and application-processing-before-finish path. It never blindly finishes a current entitlement. Unknown candidates seed the same two-second retry loop; approved candidates can process and finish even when the updates listener sends nothing at launch.

A small async snapshot-loader seam makes the missing-event path testable. Generation checks surround loading and each awaited candidate delivery; restarting observation inside one callback cannot submit later candidates to an obsolete observer. Production/sandbox behavior stays unchanged and does not trigger the extra scan. This is recovery for the demonstrated local entitlement/unfinished discrepancy, not a claim of exhaustive cleanup when both entitlements and updates omit every local transaction.

Under the diagnostic argument, `storekit_unfinished_scan` reports total results and eligible candidates, `storekit_unfinished_recovery` identifies each candidate, and `storekit_finish_requested`, `storekit_finish_returned`, and `storekit_finish_snapshot` record the finish path and whether the same ID appears in a subsequent unfinished snapshot. An immediate snapshot is observational, not a guarantee about eventual UI propagation. An empty unfinished sequence must be distinguished from a stale manager warning; it must not justify forcing a finish from the entitlement list.

Independent design and behavioral reviews found no blocking findings. Five new tests cover approved recovery without a prior update (including actual service access before finish), recovered pending data followed by silent approval, stop during snapshot loading, stop/restart between two candidates, and no loading when observation is stopped. All **22 focused tests in two suites** passed on the separate iOS 27.0 simulator using Xcode 27.0 (`/private/tmp/NextSeasonUnfinishedRecovery.xcresult`). The final `SKTesting` build, including the unfinished-scan count diagnostics, also succeeded for generic iOS Simulator (arm64 and x86_64). `git diff --check` passed. No full suite or owner transaction mutation was performed.

Next manual check: rebuild/run `SKTesting` with the existing approved transaction intact and inspect the warning plus these diagnostic lines. Do not create another purchase merely to clear the warning. A cleared existing transaction still needs the separate fresh 4C pending→relaunch→live approval→finished→N-untracked check before acceptance.

## Owner verification: approved recovery passed

Later October 30, the owner confirmed that the unfinished warning disappeared and Plus remained intact after the latest rebuild/run. **The existing approved-transaction recovery check passes on the owner's observation.** No new console or screenshot was supplied, so this records the observed UI result rather than independently confirming individual finish diagnostics.

This does not yet pass the full fresh 4C sequence: pending after relaunch must stay limited, approval while the app remains running must restore Plus and finish, and abandoned N must remain untracked. Approval while closed and decline checks also remain pending. No further code or test changes were made to record this result.


## Claude review follow-up: purchase outcomes and cancellation

The owner subsequently reported that the full fresh **4C passed** on the candidate preceding this follow-up, and authorized corrections for the two concrete review findings. That pass is preserved; the shared queue changes below require a focused repeat on the updated candidate. The owner also confirmed deleting the approved test transaction removed Plus when the app was reopened, matching the entitlement-refresh path.

Risk remains **high** because delivery ordering, cancellation and simulated-access completion interact. Independent design review approved per-ID shared flights and required an additional adversarial pending-result handoff scenario before implementation. Sources remain Apple purchase results, unfinished transactions and finish semantics cited above; these changes introduce no new interpretation of approval states.

Changes:

- Concurrent same-ID local deliveries share one in-flight validation/processing/finish. Waiting callers resume after completion; stopping drains waiters and invalidates ownership. Canceled joiners detach by flight token and waiter ID without canceling the owner. Cancellation before continuation registration is checked explicitly.
- A canceled owner retains its candidate for independent observer/timer recovery when the observation generation remains valid. The canceled purchase caller still reports cancellation; observation stop/restart never queues obsolete work.
- A verified raw local success whose processing is unresolved returns app-level **pending**, rather than a false purchase-verification error. Signature failures remain failures. If an observer owns the shared delivery, the direct purchasing caller receives its own acknowledgement after that already completed delivery, with no additional finish. This preserves its verified customer-purchase evidence and simulation completion.
- The service records a bounded in-memory per-product marker only after a new customer update resolves actual paid access in the same simulation session. It can recognize that completion even when it occurs before the purchase returns pending. Pending matching is evaluated after the entitlement refresh so registration during a suspended refresh is recognized too. Existing entitlement, renewal, unrelated product and older session events cannot alone satisfy this evidence.
- The lifecycle test now emits an actual transaction callback instead of calling the refresh method directly under an inaccurate callback assertion.

Production/sandbox/tip delivery paths and the subscription-state policy are unchanged. The simulation handoff correction applies wherever the testing simulation is available; it does not change normal entitlement policy or persist purchase/add state.

| Scenario | Required result | Evidence |
|---|---|---|
| Local status lag after verified success | Pending, no false error or premature access/finish | New completion bridge + real-service integration test |
| Later valid approval | Plus and current requested simulation complete | Controlled automatic retry test |
| Listener wins concurrent purchase delivery | Success, direct acknowledgement, shared finish once | Controlled listener/purchase integration test |
| Update completes before pending returns | Current requested simulation ends | Real-service handoff test |
| Pending registers during refresh | Completion sees registration after await | Suspended refresh test |
| Renewal/unrelated product/existing access/old session | Simulation stays enabled | Negative handoff tests and existing simulation suite |
| Cancellation after validation | Caller canceled; recovery retained and later finished | Controlled cancellation and independent timer test |
| Canceled joined caller | Owner continues; no obsolete caller acknowledgement | Continuation/cancellation test |
| Stop/restart with joined callers | Waiters released; stale owner cannot consume replacement | Controlled generation test |

Independent behavioral review found no blocking findings. The focused Xcode 27.0 / iOS 27.0 simulator run passed **83 tests in six suites**: `LocalPurchaseCompletionTests`, `StoreTransactionDeliveryTests`, `XcodeSubscriptionValidationTests`, `PurchaseServiceTests`, `FreeTierSimulationTests`, and `PurchaseServiceEntitlementOrderingTests`. Result: `/private/tmp/NextSeasonClaudeFollowup.xcresult`. App and test targets compiled; `git diff --check` passed. No full suite or owner simulator transaction mutation was performed.

Review disposition:

- **Findings 2 and 3:** corrected with the regression coverage above.
- **Finding 1:** remains an unverified platform scenario, not a confirmed code defect or an accepted release limitation. Older/different transaction snapshots are already rejected, but an actual pending ID returned with a terminal history state still needs observation. No speculative clock/expiration restriction was added. Test repurchase after expiry/refund and pending plan changes with existing access, recording transaction/original IDs and reset method.
- **Finding 4:** unresolved local-state/decline behavior remains a manual verification item. No arbitrary timeout converts uncertainty into approval or silently discards a valid delayed request. No claim of decline completeness is made.
- **Finding 5:** overlapping in-flight processing now coalesces. Future ordinary StoreKit redeliveries can still receive the existing idempotent service processing; global exactly-once callbacks are not promised.
- **Integration coverage:** the new tests exercise the same local completion bridge as the live client, but do not invoke StoreKit's purchase sheet or prove its real status mapping. The failed isolated StoreKitTest probe recorded earlier remains non-evidence. Manual platform testing remains necessary.
- **Swap file:** the pre-existing untracked Vim swap file remains untouched and must not be included in an eventual owner commit.

Minimum owner recheck after rebuilding: a normal local Xcode purchase with Ask to Buy off and Simulate Free Tier on must succeed without a spurious error, unlock Plus, turn simulation off, and finish. Then turn Ask to Buy on, turn simulation off, reset to Free, and repeat fresh **4C** (pending relaunch stays limited; live approval grants Plus; transaction finishes; abandoned N stays untracked). This is a targeted repeat of the changed path, not a request to repeat the full suite. Approval while closed, decline and the history-sensitive scenarios remain distinct manual checks.


## Owner verification: updated candidate checks passed

After the Claude-review follow-up, the owner confirmed the requested manual tests passed: fresh **4C** and the normal local Xcode purchase/simulation-ending check. The owner deleted the prior test transaction to establish a fresh purchase state after an already-owned error with that transaction still present. This is owner-reported acceptance of the requested scenarios; no new console or screenshot was supplied.

The existing approved-transaction recovery pass, the prior full 4C pass and this updated-candidate pass are all preserved. No additional 4C repeat is required for this documentation-only update. Deleting the earlier transaction establishes a fresh-purchase setup; it does not verify repurchase with expired/refunded history, a pending plan change with existing access, approval while closed, or decline. Those remain separate cases, and no broader release/full-suite pass is inferred.

No app code changed and no tests or simulator mutations were performed by the agent to record these results. The owner's StoreKit configuration edits remain untouched.
