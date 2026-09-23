# NextSeason — App Store Readiness Roadmap

## Purpose

This roadmap captures the work remaining before NextSeason’s first public App Store release. It covers product changes required for release, engineering and reliability work, final validation, and App Store submission.

Completed MVP work is documented elsewhere and is not repeated here.

# Product and Engineering Readiness

## Search Coverage (Complete)

TVMaze already provides fuzzy matching, alternate-title support, partial-title matching, punctuation tolerance, and relevance ordering. However, the current ten-result limit must be eliminated before the first App Store release.

- Evaluate one or more search-focused providers that can provide broader result coverage.
- Continue using the most appropriate metadata source for season tracking.
- Preserve TVMaze relevance ordering where it remains useful.
- Map provider identifiers when a show is selected.
- Keep the search layer provider-independent so that providers can be added or replaced with minimal user impact.
- Validate common searches, ambiguous titles, alternate titles, punctuation differences, and older or less-popular shows.

### Search Analytics (Complete)

Add only the analytics needed to evaluate search quality while preserving the app’s privacy approach.

Recommended events and properties:

- `search_performed`
- Query length
- Result count
- Whether a result was selected
- Whether the selected show was already on the watchlist

## Watchlist Section Scrolling (Complete)

The watchlist currently uses `List` with `Section`. Native pinned section headers allow rows to scroll beneath the header, which creates an unattractive text-over-text effect in the current design.

- Preserve the native sectioned `List` behavior, including pinned section headers.
- Ensure pinned section headers remain visually distinct from the content scrolling beneath them.
- Use an opaque app-background treatment on section headers so underlying text does not show through or interfere with readability.
- Verify correct behavior across Dynamic Type sizes, and accessibility settings.

## Watchlist Management (Complete)

- Support swipe-to-delete in the Watchlist, in addition to tapping the star.

## SwiftData Migration Strategy (Complete)

- Established a SwiftData migration strategy for future persistent-model changes.
- Verified that the current schema and persistence architecture support migration without discarding user data.
- Documented the requirement to test migrations before shipping schema changes.
- Structured the project to support fixture-based migration testing as schemas evolve.

## Persistence Recovery (Complete)

- Replaced the startup `fatalError` with a user-facing recovery flow.
- Logs diagnostics before attempting recovery.
- Explains the consequences before resetting local data.
- Allows the user to export diagnostics before resetting.
- If watchlist data can still be read, offers the user the option to export it before resetting.
- Provides a clear **Reset Local Data** action when recovery is not possible.

## Crash-Loop Prevention (Complete)

- Detects repeated launch failures while avoiding false positives from normal app termination.
- Offers a safe recovery path rather than repeatedly crashing.
- Preserves useful diagnostics for troubleshooting.
- Recovery behavior has been tested to ensure it does not itself create a new launch loop.

## Accessibility Review (Complete)

Complete a final accessibility pass and address everything that can reasonably be corrected before release.

- Verify VoiceOver labels, values, hints, traits, and navigation order.
- Verify Dynamic Type at the largest accessibility sizes.
- Verify sufficient contrast throughout the app.
- Verify controls remain usable with Button Shapes, Increase Contrast, Reduce Transparency, and Reduce Motion enabled.
- Verify that state is not communicated by color alone.
- Test empty, loading, error, and recovery states.
- Added explicit accessibility labeling for the Watchlist search control so VoiceOver does not derive an incorrect label from the SF Symbol.

## Watchlist Export (Complete)

- Exports the complete stored watchlist as a CSV file using the standard iOS share sheet.
- Includes show name, TVMaze ID, and TVDB ID when available.
- Export is available to both free and Plus users and does not require an active subscription.
- Includes all stored shows, including shows above the free-tier limit after a Plus subscription has expired.
- Produces a CSV intended to open successfully in common spreadsheet applications such as Numbers and Excel.
- Is also available from the persistence-recovery flow when watchlist data can still be read.

Import and restoration from an exported watchlist are not required for the initial App Store release; see the Product Evolution Roadmap.

## StoreKit (Implementation Complete)

See [`../Post-MVP/NextSeason - Monetization Strategy Roadmap`](../Post-MVP/NextSeason%20-%20Monetization%20Strategy%20Roadmap.md) for the proposed pricing and purchase structure.

- Implemented StoreKit 2 purchasing and entitlement management for NextSeason Plus.
- Supports annual subscription and lifetime purchase options.
- Implements optional consumable tips through **Support NextSeason**.
- Supports purchase restoration and beta-user grandfathering.
- Requests an App Store review after the first production show notification, at most once per app version.
- Provides a permanent **Write a Review** link in About.
- Production products, pricing, legal links, and App Store configuration must be finalized and validated before release.

# Documentation Readiness

## AI-Assisted Development Workflow (Complete)

[`AI-Assisted Development Workflow.md`](../AI-Assisted%20Development%20Workflow.md) documents how AI was used during development, including:

- Why AI-assisted development was used.
- The distinct roles of ChatGPT and Cursor.
- How generated code and recommendations were reviewed and validated.
- Which product, design, and engineering decisions remained mine.
- Links to representative transcripts, such as initial architecture, accessibility review, performance review, analytics, TestFlight preparation, and README review.

## Documentation Review (Initial Review Complete)

- Verify that documentation reflects the release candidate rather than an earlier MVP state.
- Check all links among documentation files.
- Remove references to diagrams that are no longer included.
- Update README screenshots to match the release candidate.
- Verify that all repository links point to the public repository.
- Remove internal-only notes, temporary instructions, and obsolete planning text.
- Perform a final documentation sync against the release candidate immediately before submission, including README screenshots, monetization details, support/privacy URLs, and any implementation changes made since the main documentation review.

# App Store Submission Checklist

These tasks are listed in approximately sequential order.

## Legal and Business

### Complete

- Receive the D-U-N-S Number for Trial by Fyre, LLC.
- Complete tax information.
- Submit banking information.
- Establish `support@getnextseason.com` as the support email address.
- Establish email as the primary user-support channel.

### In Progress — Awaiting Apple

- Convert the Apple Developer account to an Organization account — required documents submitted; awaiting Apple verification.
- Complete Small Business Program enrollment — enrollment submitted; awaiting Apple approval.
- Confirm banking information has been verified by Apple — banking details submitted; awaiting verification.

### Not Started / Remaining

- Verify company information in App Store Connect after the Organization conversion.
- Finish and publish `getnextseason.com` as the support website.
- Publish and verify the Privacy Policy.

## App Store Assets and Metadata

### Complete

- Decide whether to create an App Preview video — **No App Preview for v1.0.**

### In Progress

- App Store search/ASO research, including competitor searches and natural-language discovery terms.

Starting queries:

- tv show next season
- tv show upcoming season
- upcoming tv seasons
- new season reminder
- track tv show new seasons
- when is the next season
- when does my show come back

### Not Started / Remaining

- Export and validate the final production app icon.
- Capture App Store screenshots for every required device size.
- Write the App Store description.
- Write promotional text.
- Choose the App Store subtitle.
- Choose keywords.
- Select primary and secondary categories.
- Prepare copyright information.
- Complete ASO research and use the results to finalize the subtitle and keyword field.

## Privacy and Compliance

### Not Started / Remaining

- Complete the App Privacy questionnaire and Privacy Nutrition Label.
- Verify that the App Privacy answers accurately describe the release build.
- Confirm export-compliance/encryption questionnaire answers.
- Review required legal acknowledgements and third-party licenses.
- Verify that external services and data sources are disclosed where required.
- Cross-check the published Privacy Policy against the App Privacy answers and actual release-build behavior.

## Final Quality Pass

### Not Started / Remaining

- Complete a full regression test.
- Test on iOS 27 (current public release).
- Test on iOS 26.
- Test on iOS 18 (minimum supported OS).
- Verify behavior and UI across both pre-Liquid-Glass and Liquid-Glass system designs.
- Verify upgrade from earlier TestFlight builds.
- Verify a clean installation.
- Verify notification permission flows.
- Verify background refresh behavior.
- Verify behavior with notifications disabled.
- Verify behavior with Background App Refresh disabled.
- Verify Dynamic Type and VoiceOver.
- Verify English-only localization assumptions and text expansion.
- Verify offline and poor-network behavior.
- Run Instruments one final time for leaks, memory growth, and performance problems.
- Review all user-facing error messages and recovery paths.
- Include SwiftData migration testing in release validation whenever a schema change is introduced.
- Maintain representative persistent stores from previously shipped schema versions for upgrade testing.

## TestFlight Release Candidate

### In Progress

- The current TestFlight build is the **provisional v1.0 release candidate**; no code changes have been made since it was distributed.
- Existing external testers continue to receive and install TestFlight updates.
- Continue evaluating any remaining beta feedback.

### Remaining Before Submission

- If no further code changes are required, designate the current TestFlight build as the final v1.0 release candidate.
- If code changes are made, create a new release-candidate build and revalidate the affected areas.
- Remove, hide, or appropriately gate developer-only diagnostics.
- Confirm which diagnostics intentionally remain available to users.
- Complete the Final Quality Pass against the final build.
- Confirm the final build matches the App Store screenshots and description.
- Set or confirm final v1.0 version and build numbers.
- Treat the accepted release-candidate build as the intended App Store binary; code changes after final validation require a new build and appropriate revalidation.
- Create and push a `v1.0` Git tag preserving the exact code and documentation shipped to the App Store.

## App Store Connect

### In Progress

- Configure NextSeason's App Store Connect record and associated agreements.
- Configure production In-App Purchases for Plus and the tip jar as the Organization-account setup permits.
- Complete pricing and availability configuration as the necessary agreements and banking verification become active.

### Remaining

- Create/configure the v1.0 App Store version.
- Select the final release-candidate build.
- Upload final screenshots and other required assets.
- Add the final description, subtitle, promotional text, keywords, categories, support URL, and Privacy Policy URL.
- Select countries and regions.
- Configure and verify the age rating.
- Complete App Review contact information.
- Write App Review notes explaining anything reviewers need to know, particularly the free/Plus behavior and purchases.
- Provide a demo account only if App Review actually needs one; NextSeason does not otherwise require an account.
- Complete final pricing and availability checks for the app and IAPs.
- Verify that all agreements, tax, and banking requirements show as active.
- Perform a final App Store Connect review as if seeing the listing for the first time, checking URLs, spelling, screenshots, pricing, territories, privacy information, and review notes.
- Submit the final build and metadata for App Review.
- Monitor App Review status and respond promptly to reviewer questions.

## Launch

### Decisions to Make Before Submission

- Decide between automatic release and manual release after App Review approval.
- Decide on the exact launch-announcement channels and timing.

### Launch

- Publish the production website at `getnextseason.com`.
- Verify the live App Store listing, screenshots, pricing, purchases, support URL, and Privacy Policy URL.
- Publish launch announcements through the selected channels, potentially including the project website, GitHub, Substack, and appropriate social accounts.
- Update the Trial by Fyre website to feature NextSeason as a released product.
- Celebrate. 🥂

### Immediate Post-Launch

- Monitor crash reports and App Store Connect diagnostics.
- Monitor App Store reviews and `support@getnextseason.com`.
- Respond promptly to serious launch issues and App Review follow-up, if any.
- Verify that purchases and entitlements behave correctly in production.
- Verify that background refresh and production notifications are behaving as expected.
- Prioritize launch-related fixes before beginning major new feature development.
