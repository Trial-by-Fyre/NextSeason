//
//  DiagnosticsDocumentationView.swift
//  NextSeason
//

import SwiftUI

/// Help sheet for the beta Diagnostics screen.
@MainActor
struct DiagnosticsDocumentationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    documentationText(DiagnosticsDocumentationCopy.overview)
                }

                Section("App") {
                    documentationText(DiagnosticsDocumentationCopy.appSection)
                }

                Section("Subscription Testing") {
                    documentationText(DiagnosticsDocumentationCopy.subscriptionTestingSection)
                }

                Section("Beta validation — Background") {
                    documentationText(DiagnosticsDocumentationCopy.betaValidationBackgroundSection)
                }

                Section("Beta validation — Foreground") {
                    documentationText(DiagnosticsDocumentationCopy.betaValidationForegroundSection)
                }

                Section("Beta validation — Simulation") {
                    documentationText(DiagnosticsDocumentationCopy.betaValidationSimulationSection)
                }

                Section("Beta actions") {
                    documentationText(DiagnosticsDocumentationCopy.betaActionsSection)
                }

                Section("Launch investigation") {
                    documentationText(DiagnosticsDocumentationCopy.launchInvestigationSection)
                }

                Section("Usage") {
                    documentationText(DiagnosticsDocumentationCopy.usageSection)
                }

                Section("Share report") {
                    documentationText(DiagnosticsDocumentationCopy.shareReportSection)
                }
            }
            .navigationTitle("Diagnostics Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func documentationText(_ markdown: String) -> some View {
        Text(attributedMarkdown(from: markdown))
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributedMarkdown(from markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(markdown)
    }
}

#if DEBUG
    #Preview {
        DiagnosticsDocumentationView()
    }
#endif
