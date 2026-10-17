//
//  SearchAutomationModifier.swift
//  NextSeason
//

import SwiftUI

/// Reads automation environment hooks (set in `ContentView`) and bridges them to
/// `SearchViewModel` state. Feature views apply this modifier; they do not wire
/// the coordinator themselves.
///
/// Guards with `ProfileFlowConfiguration.isEnabled` so normal launches never
/// bump settlement tokens even though `ContentView` always installs the hooks.
struct SearchAutomationModifier: ViewModifier {
    @Environment(\.automationSearchQuery) private var automationSearchQuery
    @Environment(\.automationSearchRequestID) private var automationSearchRequestID
    @Environment(\.onAutomationSearchSettled) private var onAutomationSearchSettled
    @Bindable var viewModel: SearchViewModel

    func body(content: Content) -> some View {
        content
            .task(id: automationSearchRequestID) {
                guard ProfileFlowConfiguration.isEnabled,
                    let query = automationSearchQuery.wrappedValue, !query.isEmpty
                else { return }
                let error = await viewModel.runProfilingSearch(query)
                guard !Task.isCancelled else { return }
                // Clear before signaling: the runner may immediately enqueue the
                // identical query again after observing completion.
                automationSearchQuery.wrappedValue = nil
                onAutomationSearchSettled?(error)
            }
    }
}

extension View {
    /// Connects search UI to optional automation hooks supplied via environment.
    func automationSearchHooks(viewModel: SearchViewModel) -> some View {
        modifier(SearchAutomationModifier(viewModel: viewModel))
    }
}
