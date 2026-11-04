//
//  PausedWatchlistSection.swift
//  NextSeason
//

import SwiftUI

/// Bottom Watchlist section for shows paused after Plus lapsed.
///
/// Rows come from `WatchlistView` (shared frame tracking and removal), render
/// without a `NavigationLink`, and stay removable via swipe, star, or the
/// VoiceOver action. Tapping a row reactivates it into an open free slot, or
/// opens Plus at capacity. Not collapsible: it is the only place paused shows appear.
struct PausedWatchlistSection<Row: View>: View {
    let shows: [TrackedShow]
    var onDelete: ((IndexSet) -> Void)?
    @ViewBuilder let row: (TrackedShow) -> Row

    var body: some View {
        Section {
            ForEach(shows) { tracked in
                row(tracked)
            }
            .onDelete(perform: onDelete)
        } header: {
            // Concrete `Color.primary` (label color) on both lines: list section
            // headers apply their own dimmed style, and hierarchical
            // `.primary`/`.secondary` resolve relative to it, rendering too faint.
            VStack(alignment: .leading, spacing: 4) {
                Text("Paused")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "These shows are saved but aren't being tracked. Tap one to track it when one of your \(WatchlistLimitPolicy.freeShowLimit) free slots is open, or renew Plus to track all your saved shows."
                )
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.tight)
            .background(AppColor.background)
            .accessibilityIdentifier(AccessibilityID.Watchlist.pausedSection)
        }
    }
}
