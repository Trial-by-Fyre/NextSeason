# Watchlist removal cancelled on tab switch — October 27, 2026

**Status:** owner-observed behavior; intended navigation/removal rule needs confirmation. Not classified as a bug, accepted limitation, or approved behavior change. No app code changed and no independent reproduction or tests were run for this record.

## Reported sequence

1. Leave a show’s detail open in Search.
2. Switch to Watchlist and tap an active test show’s star to start an undoable removal.
3. Tap the Search tab while the Undo toast is still visible.
4. Return to Watchlist: the owner reports that removal was cancelled and the show remains saved.

The owner believes this has behaved that way all along and had assumed it intentional. The latest walkthrough 6.5 specifically used the same long-title show for the open Search detail and Watchlist removal. Whether the observation also occurs with a different open detail, no open detail, or a committed/swipe removal has not been established. Device/OS/build and recording were not supplied with this report. Do not ask ordinary testers to reproduce a matrix of timing permutations.

## Why recorded separately

Earlier [notification-navigation review](NotificationSearchNavigationReview-2026-10-19.md) and [follow-ups](2026-10-19-follow-ups.md) expected Watchlist removal to commit on a real tab switch. Mounted tests were explicitly insufficient to establish UIKit tap timing. Another existing rule cancels deferred removal when opening a Search detail. Those records are evidence to reconcile, not grounds to dismiss the owner’s observation or silently accept a new rule.

Before changing behavior, trace the real tab-selection/detail-appearance sequence and determine whether returning to an existing detail triggers the cancellation rule. Confirm the intended product policy with the owner. If a consequential mismatch is established, assess its priority then; this note does not defer an established defect or approve a fix.

## Script disposition

Removed the specialized step 6.5 from both beta regression documents and removed the accompanying expectation that tab-switch cancellation is necessarily a failure. Steps 6.1–6.4 still check ordinary star removal, Undo, re-add and swipe removal. A completed removal staying removed remains distinct from an undoable removal being cancelled during navigation.

This observation is also separate from the future-roadmap request to close a Watchlist detail after that show is removed from Search and removal has **already committed**. No implementation or schedule is assigned here.
