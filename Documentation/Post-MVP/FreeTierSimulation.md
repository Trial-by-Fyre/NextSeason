# Simulate Free Tier

In a developer build or TestFlight, open About → Diagnostics → Subscription Testing
and turn on **Simulate Free Tier**. The switch and an active notice show its state.
About also labels the watchlist capacity as simulated.

While enabled, adding a show uses the normal free-tier watchlist limit even with paid or
complimentary Unlimited. A watchlist already over the limit remains intact;
remove shows only if you want to test adding below the cap. Export and existing
show access are unchanged. No simulation code writes watchlist or entitlement storage.

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

Turn the switch off to restore actual access immediately. Restarting the app
also ends simulation; the override is deliberately session-only.

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
`NextSeasonTests/FreeTierSimulationTests.swift`.
