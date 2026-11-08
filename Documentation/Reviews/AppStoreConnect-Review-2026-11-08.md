# App Store Connect review — November 8, 2026

Reviewed the signed-in NextSeason TV record, Apple ID 6784502780, through App Store Connect. This is a release-configuration review, with a focused comparison to the working repository and published website. Findings describe the state observed on this date. App Store Connect settings were inspected only.

## Recheck after owner updates — November 8, 2026

All six main findings from the initial inspection are resolved at the configuration level.

| Initial finding | Recheck result |
| --- | --- |
| Primary category | Entertainment selected |
| Content Rights | Saved response states that the app has the necessary rights to its third-party content |
| Past pre-order date | Pre-order removed. All six selected countries now show Available on App Release. Manual release remains selected |
| Terms of Use | Standard Apple EULA URL added to the public description |
| Selected binary | Version 1.0 now selects build 55, matching the current project's build number |
| Submission contents | Draft contains seven items, including iOS version 1.0 (55), three tips, two subscriptions, and the subscription group. Submit for Review becomes enabled after the panel finishes loading |

The notification sentence in the app review notes now says “Notifications are sent only when relevant season or premiere information changes.” This resolves the wording follow-up.

Remaining follow-ups from the initial inspection are below.

- Screenshot 04 still shows Calculator behind the NextSeason notification. The earlier screenshot concern remains an editorial/review-risk judgment.
- Tip navigation is sufficient. The owner clarified that tips are directly on About under the Support NextSeason heading, which the app review notes mention. The tip-specific instruction to open About reaches those controls. The earlier suggestion assumed an additional navigation step and is withdrawn.
- The live marketing site's App Store button still points to `#`. Complete that link when the public listing is available.
- Five marketing screenshots remain present. Full-size fine-print/price verification for search, notification, and Plus remains pending from the initial inspection.

Selecting build 55 establishes the submission's build selection, but does not establish runtime acceptance of that binary. Rights were checked as a saved App Store Connect response. The underlying licenses were not re-audited. This recheck inspected the prior findings and did not repeat the earlier account, pricing, or privacy review. The app remains Ready for Review, with submission still pending.

## Initial findings before owner updates

1. **Primary category is blank.** App Information shows the “Primary” placeholder selected. Entertainment appears appropriate for the app, subject to the owner's decision. The secondary category is optional and also blank.
2. **Content Rights is incomplete.** App Information still offers “Set Up Content Rights Information.” Complete the response based on the actual rights to TV data and artwork. The review did not establish those rights or make a legal declaration.
3. **Pre-order date has passed.** Availability shows “Scheduled App Release Oct 30, 2026” and “Pre-Order Pending Developer Release” in all six selected countries. Choose an updated launch date before publishing the pre-order. Apple's setup guidance calls for an initial date two to 180 days in the future. [Apple pre-order guidance](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order)
4. **Description lacks a Terms of Use link.** Apple's Standard License Agreement is selected in App Information, but the public description contains no Terms of Use URL. Add the standard EULA URL used by the app, https://www.apple.com/legal/internet-services/itunes/dev/stdeula/. Apple's subscription guidance requires Terms of Use and Privacy Policy links in the app and App Store metadata. [Apple subscription guidance](https://developer.apple.com/app-store/subscriptions/)
5. **Confirm the final binary.** Version 1.0 currently selects build 52. The working project's build number is 55. This comparison does not establish which later builds have been uploaded or accepted as release candidates. Select the validated normal release build when ready and recheck its metadata, privacy behavior, screenshots, and review instructions.
6. **Add the app version to the submission.** The existing iOS draft contains six items — three consumable tips, two subscriptions, and their subscription group. Version 1.0 remains “Prepare for Submission” with “Add for Review” available, and the draft's Submit for Review button is disabled. Include the accepted app version in the same draft when ready. [Apple first-purchase submission guidance](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

## Screenshot and copy follow-ups

- Five iPhone marketing screenshots are uploaded in order — watchlist, show details, search, notification, and Plus. The large Dynamic Island set contains five images. The medium Dynamic Island set displays those through “Using Existing Assets,” despite showing zero directly uploaded images for that size.
- Watchlist and show-detail artwork were inspected at full size. Search, notification, and Plus were inspected through smaller browser previews. Full-size retrieval was slow, so fine print and prices in the last three images remain to be checked at a readable size against the final build.
- **Notification screenshot 04 shows Calculator behind a NextSeason banner.** Consider replacing it with an example that keeps the notification prominent and presents NextSeason more clearly. This is a review-risk assessment, not a confirmed rejection. Apple's screenshot guidance calls for showing the app in use. [App Review guideline 2.3.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)
- The review notes end with “Notifications are sent only when a show's status changes.” The preceding text and public description also discuss season announcements and premiere changes. “When relevant season or premiere information changes” would avoid interpreting “status” narrowly. Verify the final wording against the selected build.
- Tip-specific review notes say to open About. The subsequent owner clarification confirmed that the tips are directly on that page under Support NextSeason, so the suggested additional navigation instruction is unnecessary.
- The marketing website loads, but its “Download NextSeason on the App Store” link currently points to `#`. Replace it with the actual pre-order/download destination when the listing is available, consistent with the roadmap.

## Verified configuration

| Area | Observed state |
| --- | --- |
| Listing | NextSeason TV, subtitle “Don't miss the next season,” English (U.S.), version 1.0, copyright 2026 Trial by Fyre, LLC |
| App price | United States price $0.00 |
| App availability | Australia, Canada, Ireland, New Zealand, United Kingdom, United States, all configured for pre-order |
| Release method | Manual, with pre-order notice |
| Additional platforms | Apple silicon Mac and Apple Vision Pro availability unchecked |
| Distribution | Public App Store distribution |
| Age rating | Calculated 13+ in most regions, 16+ Vietnam, 14+ Brazil, 12+ Korea, with an earlier-OS global rating of 12+ |
| Age questionnaire | No social features, unrestricted browsing, advertising, gambling, medical content, or age assurance. Infrequent mature themes, profanity, horror, substance references, sexual content, violence, and weapons. Graphic sexual content and prolonged graphic violence marked none. No rating override |
| App Review | Sign-in required unchecked. Contact fields populated. Notes explain free/Plus behavior, restore, expiry/paused shows, tips, local notifications, manual refresh, and iOS background scheduling |
| Privacy Policy URL | https://getnextseason.com/privacy.html, loaded successfully |
| Support URL | https://getnextseason.com/support.html, loaded successfully with FAQ and support email |
| Marketing URL | https://getnextseason.com, loaded successfully |
| Privacy labels | Product Interaction and Coarse Location, used for Analytics, displayed as Data Not Linked to You |
| Business readiness | Free Apps and Paid Apps agreements Active. Bank account and U.S. W-9 Active. DSA compliance Active |
| Accessibility labels | Setup has not been completed. Declare supported features after checking Apple's support criteria and the final build |
| Billing grace period | Not configured |
| Streamlined purchasing | On |

The published privacy policy describes three remote Aptabase events — launch, search metrics/outcome, and search-result selection/already-on-watchlist. The current source's `remoteEvent` whitelist matches these categories and omits search text, show names, and show identifiers. This is source-level agreement, not verification of build 52's actual network traffic or a completed analytics-consent assessment. The roadmap's consent review remains a separate task.

## Purchases

Both Plus plans use subscription group 22429434 and service level 1. Family Sharing is off for both. Their selected-availability price tables contain the same six countries as the app. Both have English display names/descriptions, a review screenshot attached, and are Ready for Review and added to the draft. Multiseat purchases are not allowed. Annual monthly-installment availability is not configured.

| Country | Monthly | Annual |
| --- | --- | --- |
| Australia | AUD 2.99 | AUD 14.99 |
| Canada | CAD 2.99 | CAD 12.99 |
| Ireland | EUR 1.99 | EUR 9.99 |
| New Zealand | NZD 3.99 | NZD 19.99 |
| United Kingdom | GBP 1.99 | GBP 9.99 |
| United States | USD 1.99 | USD 9.99 |

Product IDs match the current source — `com.trialbyfyre.nextseason.plus.monthly` and `com.trialbyfyre.nextseason.plus.annual`. The US prices agree with the monetization roadmap.

All three tips are Consumable, Ready for Review, added to the draft, and have a review screenshot attached. Each reports six selected countries. Their exact selected-country lists and the visual contents of purchase review screenshots were not inspected.

| Tip | Product ID suffix | US price | Display description |
| --- | --- | --- | --- |
| Trailer | `tip.trailer` | USD 0.99 | A small tip to support NextSeason. |
| Pilot | `tip.pilot` | USD 2.99 | A tip to support NextSeason. |
| Hit Show | `tip.hitshow` | USD 4.99 | A generous tip to support NextSeason. |

The IDs share the `com.trialbyfyre.nextseason.` prefix and match the source. These are observed production prices. The roadmap still describes tip prices as provisional.

## Review limits

This review does not establish final-build acceptance, purchase execution, notification delivery, data/artwork licensing, analytics consent compliance, or complete screenshot-to-binary equivalence. TestFlight tester administration, optional marketing campaigns, and account access administration were outside this release-listing pass. No app tests were run. Existing working-copy changes were left intact.
