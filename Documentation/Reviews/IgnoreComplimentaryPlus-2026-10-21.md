# Ignore Complimentary Plus — scenario checklist (2026-10-21)

Risk: medium-high. Testing-only override in the entitlement decision, gated like
Simulate Free Tier. Independent design and implementation review requested.

## Design

- `PurchaseService` gains a session-only `ignoreComplimentaryPlusRequested` flag.
  Effective complimentary access = stored grant AND NOT (override available AND
  requested). Every effective-access read (`confirmedWatchlistAccess`,
  `isUnlimitedWatchlist`, `isComplimentary`, `restoreNotice`, initial-entitlement
  waiters) goes through that one value, so watchlist limits, pausing/resuming,
  the paywall, About, Restore feedback, and notification/background refresh (which
  follow pause flags) all see the same decision.
- Availability reuses the Simulate Free Tier gate: Debug always; Release only with
  a verified sandbox `AppTransaction` (TestFlight), re-checked on every read. Release
  ignores test injection. TestFlight and App Store share one binary, so the override
  cannot be compiled out of TestFlight; the verified-provenance gate is the boundary.
- Never writes `PlusEntitlementStore`, UserDefaults grant keys, or Keychain. The
  stored grant stays readable as `hasStoredComplimentaryPlus` for Diagnostics.
- Simulate Free Tier still masks all access and wins when both are on. The toggles
  are independent: neither changes the other, and simulation's purchase auto-end
  leaves the override on.
- Relaunch testing aid: Diagnostics shows StoreKit Plus status (raw StoreKit, never
  complimentary) and whether the complimentary grant is stored, both visible
  regardless of the switch. Debug-only launch argument `-IgnoreComplimentaryPlus`
  starts a process with the override already on, before the first reconcile (Xcode
  runs only; compiled out of Release).

## Scenarios

| # | Scenario | Expected | Verification |
| --- | --- | --- | --- |
| 1 | Grant stored, switch off | Unchanged: Unlimited, About shows complimentary, restore notice nil | Unit + existing tests |
| 2 | Grant stored, switch on, no subscription | Free limit; >3 active shows pause (3 oldest stay); alert; About “Up to 3 shows”; restore notice “No active…” | Unit |
| 3 | Switch on, active subscription | Unlimited; About “Plus”; restore notice nil | Unit |
| 4 | Switch on, subscription expires (recheck/foreground) | Access false → shows pause like a real lapse | Unit (stub flip + refresh) |
| 5 | Switch on, purchase/resubscribe succeeds | Unlimited; paused shows resume; paywall dismisses | Unit |
| 6 | Switch on, restore finds subscription | Unlimited, notice nil | Unit |
| 7 | Switch on, StoreKit unverified | Confirmed access nil (no pausing); adds use free limit; unverified restore notice; About “Unable to Verify” | Unit |
| 8 | Switch on, StoreKit still loading | Adds wait for StoreKit (not complimentary); no pausing | Unit |
| 9 | Switch turned off while an add waits | Waiter resumes with Unlimited | Unit |
| 10 | Purchase/restore fails or is cancelled with switch on | Error shown; access unchanged; switch stays on | Unit |
| 11 | Simulate on + Ignore on | Free (simulation wins); turning simulation off → StoreKit only | Unit |
| 12 | Simulate on + Ignore on, verified purchase | Simulation ends; Ignore stays on; Unlimited via StoreKit | Unit |
| 13 | Override unavailable (Release without verified sandbox) | Setter refuses; reads ignore an earlier request | Unit (injected gate) |
| 14 | Grant storage after toggling on/off | UserDefaults keys and persistence unchanged; grant effective again when off | Unit |
| 15 | Relaunch | Override off; grant effective; paused shows resume + catch up; Diagnostics StoreKit row shows real status | Manual |
| 16 | Relaunch from Xcode with `-IgnoreComplimentaryPlus` | Override on from launch; cold-launch pausing/adds follow StoreKit only | Manual |
| 17 | Reinstall | Grant recovered from Keychain; StoreKit row shows subscription status; Restore with switch on gives StoreKit-only feedback | Manual |
| 18 | App Store build | Control hidden; override inactive | Gate unit tests + Release compile |

## Cannot reliably test

- App Store production gating at runtime (would need a production install); covered by
  the gate logic tests and the shared Simulate Free Tier boundary.
- TestFlight cold launch with the override already on (launch arguments are Xcode-only).
  After a TestFlight relaunch, read the Diagnostics StoreKit row, then re-enable.
- Background refresh launched by the system with the override on: a new process starts
  with the override off, so complimentary access resumes paused shows.

## Reviews

Design review (independent, before coding), adopted: override applied to the raw
reads in `refreshComplimentaryEntitlement` / `waitForInitialEntitlementResolution`
(test 8); `BetaBuildAvailability.refresh()` keeps an earlier verified sandbox result
after a thrown lookup, so closing Diagnostics mid-lookup or going offline cannot
silently drop the override and resume shows; About reminder; raw StoreKit row with
expiration and read time; reinstall/account caveats below.

Implementation review (independent), dispositions:
- "rawStoreKitStatus will fail" — not applicable: `PlusEntitlementStatus.init` drops
  non-active expirations; the test passes.
- Gate-stability change has no automated test (Release-only code) — manual TestFlight check below.
- A request survives a gate drop and reapplies if verification later succeeds —
  accepted limitation candidate (same as Simulate Free Tier; rare in TestFlight).
- Diagnostics Copy/Share report omits override state (breadcrumb only) — follow-up.
- New processes (including background launches) start with the override off — accepted by design.

Verification: 96 focused unit tests passed (new suite + simulation, entitlement store,
presentation, purchase service). Release configuration compiles; the launch argument is
absent from the Release binary. No UI tests touch these screens; none run.

## Manual testing

Accounts: Debug builds from Xcode use Settings → Developer → Sandbox Apple Account.
TestFlight uses your Apple Account in the TestFlight sandbox. Subscriptions from one
generally won't appear in the other, and installing Debug over TestFlight replaces it
(data kept). Reinstall from TestFlight before TestFlight checks.

1. Open Diagnostics, turn on Ignore Complimentary Plus. Confirm the orange label, About's
   reminder, "Complimentary grant: Stored", and StoreKit Plus status.
2. No subscription: watchlist >3 active shows pauses all but the 3 oldest; Restore says
   no active subscription.
3. Subscribe: StoreKit Plus becomes Active; shows resume; paywall dismisses.
4. Expiration: cancel renewal (Sandbox account settings or TestFlight subscription
   management), wait past "Expires or renews" (+5 min recheck, or foreground the app):
   status Not active, shows pause. Resubscribe to resume.
5. Relaunch: force-quit and reopen. The switch is off and access is Unlimited
   (complimentary). Read StoreKit Plus first: that row, not Unlimited, shows whether the
   subscription persisted. Then turn the switch back on to see StoreKit-only access.
   Debug only: add `-IgnoreComplimentaryPlus` in Edit Scheme → Run → Arguments to start
   with the override on (cold-launch pausing/adds).
6. Reinstall: delete and reinstall. Grant should return from Keychain ("Stored").
   StoreKit Plus may already be Active before Restore; that is normal. With the switch on,
   Restore should give no notice when active and "No active…" when not.
7. Gate stability (TestFlight): switch on, close/reopen Diagnostics, go offline and
   foreground the app; the switch should stay on.
8. Grant intact: turn the switch off (or relaunch); About shows complimentary Plus.

Cannot reliably test: App Store runtime gating (needs a production install); TestFlight
cold launch with override on; system background launches with override on; billing
grace period and refunds outside a local StoreKit configuration.
