//
//  AutomationEnvironment.swift
//  NextSeason
//

import SwiftUI

/// Optional hooks that let an external driver (today: `ProfileFlowRunner`) observe
/// async UI work without feature views knowing about profiling.
///
/// **Wiring lives in `ContentView` only.** Search and detail screens read these
/// values from the environment; they never take profiling parameters in their
/// initializers. That keeps Instruments tooling out of the public surface of
/// feature views while still allowing the runner to inject a search query and
/// wait until debounced search / detail load settle.
private struct AutomationSearchQueryKey: EnvironmentKey {
    @MainActor static let defaultValue: Binding<String?> = .constant(nil)
}

private struct AutomationSearchRequestIDKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct AutomationSearchSettledKey: EnvironmentKey {
    @MainActor static let defaultValue: ((String?) -> Void)? = nil
}

private struct AutomationDetailLoadedKey: EnvironmentKey {
    @MainActor static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// One-shot search query injection. The runner sets this on
    /// `AppNavigationCoordinator`; `SearchAutomationModifier` copies it into
    /// `SearchViewModel` and clears it. Default is inert (`.constant(nil)`).
    @MainActor var automationSearchQuery: Binding<String?> {
        get { self[AutomationSearchQueryKey.self] }
        set { self[AutomationSearchQueryKey.self] = newValue }
    }

    /// A distinct identity for each request, including identical query strings.
    var automationSearchRequestID: Int {
        get { self[AutomationSearchRequestIDKey.self] }
        set { self[AutomationSearchRequestIDKey.self] = newValue }
    }

    /// Called when search reaches a settled outcome (`.results`, `.empty`, or
    /// `.failed`); the argument is nil on success, or the failure message. Only invoked while `-ProfileFlow` is active; see
    /// `SearchAutomationModifier`. Default is `nil` (no-op).
    @MainActor var onAutomationSearchSettled: ((String?) -> Void)? {
        get { self[AutomationSearchSettledKey.self] }
        set { self[AutomationSearchSettledKey.self] = newValue }
    }

    /// Called when show detail finishes loading. Inherited by pushed
    /// `ShowDetailView` instances inside the Search tab. Default is `nil` (no-op).
    @MainActor var onAutomationDetailLoaded: (() -> Void)? {
        get { self[AutomationDetailLoadedKey.self] }
        set { self[AutomationDetailLoadedKey.self] = newValue }
    }
}
