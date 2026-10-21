//
//  WatchlistRefreshFailureNotice.swift
//  NextSeason
//

import SwiftUI

/// Small, transient notice at the top of the Watchlist after a pull-to-refresh
/// fails (usually offline). Tap to dismiss; `WatchlistView` also hides it after
/// a few seconds. Saved rows are unaffected.
struct WatchlistRefreshFailureNotice: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label {
                Text(message)
                    .font(.footnote)
                    .appPrimaryText()
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppColor.warning)
            }
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.tight)
            .background(AppColor.surface, in: .capsule)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.screen)
        .padding(.top, AppSpacing.tight)
        .accessibilityLabel(message)
        .accessibilityHint("Dismisses this message")
        .accessibilityIdentifier(AccessibilityID.Watchlist.refreshFailure)
    }
}

#Preview {
    WatchlistRefreshFailureNotice(
        message: WatchlistViewModel.refreshFailedMessage,
        dismiss: {}
    )
}
