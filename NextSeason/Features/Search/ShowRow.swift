//
//  ShowRow.swift
//  NextSeason
//

import SwiftUI

/// Poster, title, and status for a show in search results or the watchlist.
struct ShowRowLabel: View {
    let name: String
    let subtitle: String
    let posterURL: URL?
    var isStale: Bool = false
    /// Optional tertiary line (genres on search, last-checked on watchlist).
    var detailLine: String?
    /// Watchlist-only footer kept separate so genre lines don't collide.
    var footer: String?
    /// Watchlist paused style (Plus lapsed): grayscale poster, lock icon, and
    /// secondary-colored title. Text stays fully opaque to keep contrast.
    var isPaused: Bool = false

    init(
        name: String,
        subtitle: String,
        posterURL: URL?,
        isStale: Bool = false,
        detailLine: String? = nil,
        footer: String? = nil,
        isPaused: Bool = false
    ) {
        self.name = name
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.isStale = isStale
        self.isPaused = isPaused
        self.detailLine = detailLine
        self.footer = footer
    }

    init(show: Show) {
        self.init(
            name: show.name,
            subtitle: show.status.displayLabel,
            posterURL: show.posterMediumURL,
            detailLine: show.genres.isEmpty ? nil : show.genres.genreDisplayLine
        )
    }

    /// TheTVDB search hit: year/status as subtitle, network as the detail line.
    /// Name and poster are TVMaze fields overlaid from the local mapping.
    init(result: TVDBSearchResult) {
        self.init(
            name: result.name,
            subtitle: result.searchSubtitle,
            posterURL: result.posterURL,
            detailLine: result.network
        )
    }

    init(tracked: TrackedShow) {
        // Paused rows omit season/premiere info and the "Updated" time: both may
        // be stale because paused shows are not refreshed.
        if tracked.isPaused {
            self.init(
                name: tracked.name,
                subtitle: String(localized: "Paused"),
                posterURL: tracked.posterMediumURL,
                isPaused: true
            )
            return
        }
        let updated = tracked.lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
        self.init(
            name: tracked.name,
            subtitle: tracked.nextSeason.headline,
            posterURL: tracked.posterMediumURL,
            isStale: tracked.isStale,
            footer: String(localized: "Updated \(updated)")
        )
    }

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            poster
                .grayscale(isPaused ? 1 : 0)
                .opacity(isPaused ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                if isPaused {
                    Text(name)
                        .font(.headline)
                        .appSecondaryText()
                    Label(subtitle, systemImage: "lock.fill")
                        .font(.subheadline)
                        .appSecondaryText()
                } else {
                    Text(name)
                        .font(.headline)
                        .appAccentText()
                    Text(subtitle)
                        .font(.subheadline)
                        .appSecondaryText()
                }
                if isStale {
                    Text("No longer on TVMaze")
                        .font(.caption)
                        .foregroundStyle(AppColor.warning)
                }
                if let detailLine {
                    Text(detailLine)
                        .font(.caption)
                        .appSecondaryText()
                }
                if let footer {
                    Text(footer)
                        .font(.caption)
                        .appSecondaryText()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [name, subtitle]
        if isPaused {
            parts.append(String(localized: "NextSeason Plus required"))
        }
        if isStale {
            parts.append(String(localized: "No longer on TVMaze"))
        }
        if let detailLine {
            parts.append(detailLine)
        }
        if let footer {
            parts.append(footer)
        }
        return parts.joined(separator: ", ")
    }

    // Intentionally duplicated with ShowDetailView.poster rather than a shared
    // PosterImage helper. Extraction and custom loaders did not fix the
    // pre-existing detail-page banding (visible on cold loads such as Try an
    // Example) and a full-decode cache made search rows slower, so keep the
    // original inline AsyncImage at each call site.
    private var poster: some View {
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: 60, height: 90)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "tv")
            }
    }
}

/// Track / untrack control shown beside a show list row.
struct ShowRowTrackButton: View {
    let showID: Int
    let showName: String
    let isTracked: Bool
    let isUpdating: Bool
    /// True while an undoable removal is pending — accurate label if VoiceOver
    /// reaches the star; undo is also on the toast and row rotor action.
    var isPendingRemoval: Bool = false
    var trackButtonIdentifier: String = AccessibilityID.Search.trackButton
    let action: (CGRect) -> Void

    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        Button {
            action(buttonFrame)
        } label: {
            Group {
                if isUpdating {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: isTracked ? "star.fill" : "star")
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .tint(isTracked ? AppColor.trackedStar : AppColor.untrackedStar)
        .disabled(isUpdating)
        .accessibilitySortPriority(isPendingRemoval ? 2 : 0)
        .accessibilityLabel(trackAccessibilityLabel)
        .accessibilityIdentifier("\(trackButtonIdentifier).\(showID)")
        .accessibilityHint(String(localized: "Adds or removes this show from your watchlist"))
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateFrame(from: geometry)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, _ in
                        updateFrame(from: geometry)
                    }
                    .onChange(of: geometry.size) { _, _ in
                        updateFrame(from: geometry)
                    }
            }
        }
    }

    private func updateFrame(from geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)
        guard frame.width > 0, frame.height > 0 else { return }
        buttonFrame = frame
    }

    private var trackAccessibilityLabel: String {
        if isUpdating {
            return String(localized: "Updating watchlist for \(showName)")
        }
        if isPendingRemoval {
            return String(localized: "Undo removing \(showName) from watchlist")
        }
        return isTracked
            ? String(localized: "Stop tracking \(showName)")
            : String(localized: "Track \(showName)")
    }
}

#if DEBUG
    #Preview {
        List {
            ShowRowLabel(show: .preview)
            ShowRowLabel(tracked: TrackedShow(from: .preview))
            HStack {
                ShowRowLabel(show: .preview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ShowRowTrackButton(
                    showID: Show.preview.id,
                    showName: Show.preview.name,
                    isTracked: true,
                    isUpdating: false
                ) { _ in }
            }
        }
    }
#endif
