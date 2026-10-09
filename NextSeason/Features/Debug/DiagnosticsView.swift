//
//  DiagnosticsView.swift
//  NextSeason
//

import SwiftUI

// Optional UI presentation callback (nil = unavailable), not a required injected
// service — kept here beside Diagnostics rather than in a `+Environment` file.
private struct OpenDiagnosticsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Presents the Diagnostics screen when set by the app root (beta / DEBUG).
    var openDiagnostics: (() -> Void)? {
        get { self[OpenDiagnosticsKey.self] }
        set { self[OpenDiagnosticsKey.self] = newValue }
    }
}

/// Beta / TestFlight diagnostics screen: usage counters, launch triage, and
/// explicit actions that exercise refresh + notification pipelines without
/// relying on live TVMaze season changes. Share / Copy export the same text
/// built by `AnalyticsDiagnosticsReport`.
@MainActor
struct DiagnosticsView: View {
    @Environment(\.analytics) private var analytics
    @Environment(\.notificationService) private var notificationService
    @Environment(\.watchlistRepository) private var repository
    @Environment(\.watchlistRefreshService) private var refreshService
    @Environment(\.betaRefreshDiagnostics) private var betaRefreshDiagnostics
    @Environment(\.dismiss) private var dismiss

    @State private var notificationStatus = NotificationStatusModel()
    @State private var reportText = ""
    @State private var isForceRefreshing = false
    @State private var isSendingTestNotification = false
    @State private var isSchedulingDelayedPipelineNotification = false
    @State private var isRunningSimulation = false
    @State private var simulatedUpdateRunner: DiagnosticsSimulatedUpdateRunner?
    @State private var betaBuildAvailability = BetaBuildAvailability.shared
    @State private var isShowingDocumentation = false
    #if DEBUG
        @State private var isShowingPlusStore = false
    #endif

    private var betaValidationAvailable: Bool {
        betaBuildAvailability.isAvailable
    }

    var body: some View {
        NavigationStack {
            List {
                BetaAppInfoSection(
                    channelDisplayName: betaBuildAvailability.channelDisplayName,
                    notificationsEnabledLabel: notificationStatus.diagnosticsEnabledLabel
                )

                if betaValidationAvailable {
                    betaValidationSection
                }

                #if DEBUG
                    Section {
                        Button("Show Plus Paywall", systemImage: "cart") {
                            isShowingPlusStore = true
                        }
                    } header: {
                        Text("Screenshot Tools")
                    } footer: {
                        Text("Opens the Plus paywall without changing your unlimited access.")
                    }
                #endif

                // Unexpected-termination flags + breadcrumbs for crash-like triage.
                Section {
                    let launchDiagnostics = AppDiagnosticsLogger.launchDiagnostics()
                    LabeledContent("Previous launch") {
                        Group {
                            if launchDiagnostics.previousLaunchEndedUnexpectedly {
                                Text("Ended unexpectedly ⚠️")
                            } else {
                                Text("Clean or not detected")
                            }
                        }
                        .foregroundStyle(
                            launchDiagnostics.previousLaunchEndedUnexpectedly ? .orange : .secondary
                        )
                    }
                    LabeledContent("Current launch started") {
                        formattedDateLabel(launchDiagnostics.currentLaunchStartedAt)
                    }
                    LabeledContent("Last graceful background") {
                        formattedDateLabel(launchDiagnostics.lastGracefulExitAt)
                    }
                    LabeledContent("Consecutive unexpected launches") {
                        Text("\(launchDiagnostics.consecutiveUnexpectedLaunchCount)")
                            .foregroundStyle(
                                launchDiagnostics.consecutiveUnexpectedLaunchCount
                                    >= LaunchFailureTracker.consecutiveFailureThreshold
                                    ? .orange : .secondary
                            )
                    }
                    if launchDiagnostics.previousLaunchEndedUnexpectedly {
                        LabeledContent("Prior launch started") {
                            formattedDateLabel(launchDiagnostics.previousLaunchStartedAt)
                        }
                        LabeledContent("Detected") {
                            formattedDateLabel(launchDiagnostics.unexpectedTerminationDetectedAt)
                        }
                    }

                    let priorBreadcrumbs = launchDiagnostics.priorBreadcrumbs
                    if !priorBreadcrumbs.isEmpty {
                        ForEach(priorBreadcrumbs, id: \.self) { entry in
                            Text(entry)
                                .font(.caption.monospaced())
                        }
                    }

                    let breadcrumbs = AppDiagnosticsLogger.recentBreadcrumbs()
                    if !breadcrumbs.isEmpty {
                        ForEach(breadcrumbs, id: \.self) { entry in
                            Text(entry)
                                .font(.caption.monospaced())
                        }
                    } else {
                        Text("No breadcrumbs recorded this session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Launch investigation")
                }

                // Local tallies from `AnalyticsCounters` (not remote analytics).
                Section("Usage") {
                    let counters = analytics.countersSnapshot()
                    LabeledContent("App launches", value: String(counters.appLaunches))
                    LabeledContent("Searches", value: String(counters.searchesPerformed))
                    LabeledContent(
                        "Successful searches", value: String(counters.successfulSearches))
                    LabeledContent("No-result searches", value: String(counters.noResultSearches))
                    LabeledContent("Example searches", value: String(counters.exampleSearchesUsed))
                    LabeledContent("Show detail views", value: String(counters.showDetailViews))
                    LabeledContent("Watchlist adds", value: String(counters.watchlistAdditions))
                    LabeledContent("Watchlist removals", value: String(counters.watchlistRemovals))
                    LabeledContent(
                        "Notification permission requests",
                        value: String(counters.notificationPermissionRequests)
                    )
                    LabeledContent(
                        "Notification permission grants",
                        value: String(counters.notificationPermissionGrants)
                    )
                    LabeledContent(
                        "Notification reminders scheduled",
                        value: String(counters.notificationRemindersScheduled)
                    )
                }

                Section {
                    ShareLink(item: reportText) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = reportText
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .task {
                await betaBuildAvailability.refresh()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingDocumentation = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Diagnostics help")
                    .accessibilityHint("Explains what each field and action does")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .sheet(isPresented: $isShowingDocumentation) {
                DiagnosticsDocumentationView()
            }
            #if DEBUG
                // Present the real store directly even when complimentary access hides the upgrade CTA.
                .sheet(isPresented: $isShowingPlusStore) {
                    PlusStoreView()
                }
            #endif
            .task {
                await refreshReport()
            }
            .refreshNotificationStatus(notificationStatus)
        }
    }

    /// Last refresh / simulation outcomes plus buttons that force those paths.
    @ViewBuilder
    private var betaValidationSection: some View {
        // Persisted / in-memory samples from `BetaRefreshDiagnostics`.
        Section {
            LabeledContent("Last background refresh") {
                formattedDateLabel(betaRefreshDiagnostics?.lastBackgroundRefreshAt)
            }
            LabeledContent("Next refresh window") {
                Group {
                    if let nextDate = betaRefreshDiagnostics?.nextScheduledRefreshAt {
                        Text(
                            "\(nextDate.formatted(date: .abbreviated, time: .standard)) — 12 h (production cadence)"
                        )
                    } else {
                        Text("Not scheduled yet")
                    }
                }
                .foregroundStyle(.secondary)
            }
            LabeledContent("Last background fetch result") {
                Group {
                    if let result = betaRefreshDiagnostics?.lastBackgroundFetchResult {
                        Text(result)
                    } else {
                        Text("No background refresh recorded yet.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            LabeledContent("Last background notification decision") {
                Group {
                    if let decision = betaRefreshDiagnostics?.lastBackgroundNotificationDecision {
                        Text(decision)
                    } else {
                        Text("No background notification decision yet.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let summary = betaRefreshDiagnostics?.lastSimulatedScenarioSummary {
                LabeledContent("Last simulation") {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last foreground refresh") {
                formattedDateLabel(betaRefreshDiagnostics?.lastForegroundRefreshAt)
            }
            LabeledContent("Last foreground fetch result") {
                Group {
                    if let result = betaRefreshDiagnostics?.lastForegroundFetchResult {
                        Text(result)
                    } else {
                        Text("No foreground refresh recorded yet.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            LabeledContent("Last foreground notification decision") {
                Group {
                    if let decision = betaRefreshDiagnostics?.lastForegroundNotificationDecision {
                        Text(decision)
                    } else {
                        Text("No foreground notification decision yet.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Beta validation")
        }

        // Force refresh (silent), delayed banner from a real watchlist show,
        // delayed full refresh→notify pipeline, and two-step status simulation.
        Section {
            Button {
                Task { await forceRefreshNow() }
            } label: {
                Label {
                    if isForceRefreshing {
                        Text("Refreshing…")
                    } else {
                        Text("Force Refresh Now")
                    }
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isForceRefreshing || refreshService == nil)

            notificationActionButton(
                isLoading: isSendingTestNotification,
                loadingTitle: "Sending…",
                title: "Send Test Notification",
                systemImage: "bell.badge"
            ) {
                await sendTestNotification()
            }

            notificationActionButton(
                isLoading: isSchedulingDelayedPipelineNotification,
                loadingTitle: "Scheduling…",
                title: "Schedule Pipeline Test Notification",
                systemImage: "bell.and.waves.left.and.right"
            ) {
                await scheduleDelayedPipelineNotification()
            }

            notificationActionButton(
                isLoading: isRunningSimulation,
                loadingTitle: "Running…",
                title: "Run Simulated Update Scenario",
                systemImage: "play.rectangle.on.rectangle"
            ) {
                await runSimulatedUpdateScenario()
            }
        } header: {
            Text("Beta actions")
        } footer: {
            if !notificationStatus.canDeliverVisibleAlerts {
                Text(
                    "Notification test actions require alert permission. Enable notifications in Settings, then return here."
                )
            }
        }
    }

    private func notificationActionButton(
        isLoading: Bool,
        loadingTitle: LocalizedStringKey,
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label {
                if isLoading {
                    Text(loadingTitle)
                } else {
                    Text(title)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .disabled(isLoading || !notificationStatus.canDeliverVisibleAlerts)
        .foregroundStyle(notificationStatus.canDeliverVisibleAlerts ? .primary : .secondary)
    }

    @ViewBuilder
    private func formattedDateLabel(_ date: Date?) -> some View {
        if let date {
            Text(date.formatted(date: .abbreviated, time: .standard))
                .foregroundStyle(.secondary)
        } else {
            Text("Never")
                .foregroundStyle(.secondary)
        }
    }

    private static let testNotificationDelaySeconds: TimeInterval = 5

    private func watchlistTestShow() async -> TrackedShow? {
        try? await repository.all().first
    }

    private func prepareSimulatedUpdateRunner(using template: TrackedShow?) {
        guard betaValidationAvailable, let betaRefreshDiagnostics else { return }
        simulatedUpdateRunner = DiagnosticsSimulatedUpdateRunner(
            pipelineTemplate: template,
            notifications: notificationService,
            diagnostics: betaRefreshDiagnostics,
            analytics: analytics
        )
    }

    private func recordMissingWatchlistTestShow() {
        betaRefreshDiagnostics?.recordSimulatedScenarioSummary(
            String(localized: "Track a show on the watchlist to send a test notification.")
        )
        refreshReportText()
    }

    /// Exercises production watchlist refresh with `force: true`, without scheduling alerts.
    private func forceRefreshNow() async {
        guard let refreshService, !isForceRefreshing else { return }
        isForceRefreshing = true
        // Interactive diagnostics refresh — update silently like Watchlist pull-to-refresh.
        let outcome = await refreshService.refreshAll(force: true, deliverNotifications: false)
        if let outcome {
            betaRefreshDiagnostics?.recordForegroundRefreshCompleted(
                at: .now,
                fetchResult: outcome.fetchResult,
                notificationDecision: outcome.notificationDecision
            )
        }
        isForceRefreshing = false
    }

    /// Schedules a fictional premiere announcement, preferring Lupin for screenshots.
    /// Uses a real tracked identity for tap routing without changing its saved status.
    private func sendTestNotification() async {
        guard !isSendingTestNotification else { return }
        isSendingTestNotification = true
        await notificationStatus.refresh(using: notificationService)

        let trackedShows = (try? await repository.all()) ?? []
        guard
            let tracked = trackedShows.first(where: {
                $0.name.caseInsensitiveCompare("Lupin") == .orderedSame
            }) ?? trackedShows.first
        else {
            recordMissingWatchlistTestShow()
            isSendingTestNotification = false
            return
        }

        let content = DiagnosticsSimulatedData.notificationContent(from: tracked)
        // System-scheduled delivery is more reliable than an immediate (nil-trigger)
        // request, especially when backgrounding the app to verify the alert.
        await notificationService.deliverAfterDelay(
            content,
            requestIdentifier: "debug-test-\(UUID().uuidString)",
            delay: Self.testNotificationDelaySeconds
        )
        betaRefreshDiagnostics?.recordSimulatedScenarioSummary(
            String(
                localized: "Test notification scheduled for \(tracked.name): \(content.body)"
            )
        )
        refreshReportText()

        isSendingTestNotification = false
    }

    /// Full simulated refresh → notification decision with delayed delivery (~5–10s).
    private func scheduleDelayedPipelineNotification() async {
        guard !isSchedulingDelayedPipelineNotification else { return }
        isSchedulingDelayedPipelineNotification = true
        guard let tracked = await watchlistTestShow() else {
            recordMissingWatchlistTestShow()
            isSchedulingDelayedPipelineNotification = false
            return
        }
        prepareSimulatedUpdateRunner(using: tracked)
        _ = await simulatedUpdateRunner?.runDelayedNewSeasonNotification()
        isSchedulingDelayedPipelineNotification = false
    }

    /// One step of the two-phase baseline→updated simulated status-change scenario.
    private func runSimulatedUpdateScenario() async {
        guard !isRunningSimulation else { return }
        isRunningSimulation = true
        guard let tracked = await watchlistTestShow() else {
            recordMissingWatchlistTestShow()
            isRunningSimulation = false
            return
        }
        prepareSimulatedUpdateRunner(using: tracked)
        _ = await simulatedUpdateRunner?.runNextStep()
        isRunningSimulation = false
    }

    private func refreshReport() async {
        await notificationStatus.refresh(using: notificationService)
        refreshReportText()
    }

    private func refreshReportText() {
        reportText = analytics.diagnosticsReport(
            notificationsEnabled: notificationStatus.canDeliverVisibleAlerts,
            betaRefreshDiagnostics: betaRefreshDiagnostics
        )
    }
}

#if DEBUG
    #Preview {
        DiagnosticsView()
            .environment(\.analytics, RecordingAnalyticsService())
            .environment(
                \.notificationService, NotificationService(analytics: RecordingAnalyticsService())
            )
            .environment(\.watchlistRepository, InMemoryWatchlistRepository())
            .environment(\.betaRefreshDiagnostics, BetaRefreshDiagnostics())
    }
#endif
