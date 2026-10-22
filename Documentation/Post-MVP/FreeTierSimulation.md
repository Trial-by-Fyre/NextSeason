# Simulate Free Tier

In a developer build or TestFlight, open About → Diagnostics → Subscription Testing
and turn on **Simulate Free Tier**. The switch and an active notice show its state.
About also labels the watchlist capacity as simulated.

While enabled, the app behaves exactly as if Plus had lapsed. Simulation feeds
the same `WatchlistAccessReconciler` used for real StoreKit changes, through
`PurchaseService.confirmedWatchlistAccess`, so there is no simulation-only
downgrade code:

- If more than three shows are active, the three oldest (by date added) stay
  active and the rest are **paused**. They move to the **Paused — Plus Required**
  section, can't be opened, aren't refreshed or notified, and can still be
  removed. The one-time "Some Shows Are Paused" alert appears.
- Adding a show uses the normal free-tier limit, counting active shows only.
  Adding a paused show into a free slot reactivates it.
- Nothing is deleted. Export still includes every saved show.

Turning simulation off restores actual access. If actual Plus (StoreKit or
complimentary) is valid, every paused show resumes immediately and is then
silently refreshed. Restarting the app ends simulation too, and the first
reconcile after StoreKit confirms Plus resumes the shows. Simulation writes only
the pause flags on saved rows (and the pending-alert flag). It never writes
entitlement storage.

Try adding a show beyond the free-tier limit to open the Plus paywall. A successful monthly or annual
purchase started during the current simulation ends it once its verified customer
purchase transaction confirms active Plus. If that purchase returns pending, only
a new customer-purchase transaction for that product through transaction updates
can end simulation, after active Plus is confirmed.

Renewals (including renewals of a pending product), tips, cancelled/failed purchases,
unrelated transactions, entitlement refreshes, and restore scans do not end
simulation. Transaction reason comes from StoreKit's verified payload, rather than
inferring a purchase from a new transaction ID. Toggling simulation clears pending
tracking; a completion from an earlier simulation cannot turn off a new session.

Turn the switch off to restore actual access immediately (resuming paused shows
when actual Plus is valid). Restarting the app also ends simulation; the
override is deliberately session-only.

## Production boundary

Debug builds allow the control. Release builds require StoreKit's **verified
AppTransaction** environment to be sandbox (TestFlight). Unverified data and
receipt-name fallback cannot authorize this override. A sandbox subscription
transaction in an App Store app does not
qualify: the gate checks app provenance, not purchase provenance. The service
checks this gate both when enabling and when computing effective access.
Release ignores the developer-only test availability injection.

The service preserves actual StoreKit and complimentary access independently;
only effective watchlist access changes. Swift Testing coverage lives in
`NextSeasonTests/FreeTierSimulationTests.swift` and, for pausing and resuming,
`NextSeasonTests/SubscriptionDowngradeTests.swift`.

# Ignore Complimentary Plus

Diagnostics → **Ignore Complimentary Plus** hides permanent complimentary Plus so
real StoreKit subscriptions alone decide access (purchase, expiration,
resubscription, restore, verification failures). It uses the same Debug /
verified-TestFlight gate as Simulate Free Tier, is session-only, and never
changes the stored grant (UserDefaults or Keychain). `PurchaseService.isComplimentary`
is the single effective decision; `hasStoredComplimentaryPlus` reports the stored
grant for Diagnostics. About shows an orange reminder while it is on.

With both switches on, Simulate Free Tier wins (free limit). They are independent:
a purchase that ends simulation leaves the override on.

The section also shows the raw last StoreKit read (status, expiration, time) and
whether the grant is stored, regardless of the switch. After a relaunch (override
off, complimentary effective again) read that row to confirm StoreKit restored
the subscription instead of relying on Unlimited access. In Debug runs from Xcode,
the `-IgnoreComplimentaryPlus` launch argument starts the process with the override
on before the first reconcile (compiled out of Release).

Like simulation, toggling writes only pause flags (and the paused-alert flag);
resumed shows get a catch-up refresh. Manual test steps and limitations:
`Documentation/Reviews/IgnoreComplimentaryPlus-2026-10-21.md`.
