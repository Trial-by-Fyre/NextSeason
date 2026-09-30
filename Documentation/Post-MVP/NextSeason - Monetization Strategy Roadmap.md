# NextSeason Monetization Strategy

## Purpose

This document describes the monetization structure for NextSeason.

The goal is to create a simple and sustainable revenue model that fits the app's core promise: NextSeason quietly remembers the shows a user cares about and lets them know when something changes.

The monetization experience should be similarly simple. It should avoid unnecessary tiers, advertising, artificial feature restrictions, and frequent prompts to spend money.

The initial monetization structure has been implemented using StoreKit 2. Launch pricing is $1.99/month or $9.99/year for NextSeason Plus.

## Guiding Principles

The monetization model should:

- Allow users to experience the core value of NextSeason before paying.
- Provide ongoing revenue to support maintenance of the app and its third-party data integrations.
- Keep the distinction between free and paid service easy to understand.
- Avoid adding features or complexity merely to justify a subscription.
- Avoid advertising and the privacy, maintenance, and user-experience costs associated with ad networks.
- Avoid repeatedly interrupting or pressuring users to make purchases.
- Offer monthly billing flexibility and a better-value annual option.
- Avoid taking functionality away from users merely because a paid entitlement expires.

## Free Tier

NextSeason is free to download and use with a limited watchlist.

### Watchlist Limit

**Up to 3 shows**

The free tier does not expire. Shows on the free watchlist receive the same tracking and notification functionality as shows on a paid watchlist.

This replaces the previously considered seven-day trial.

A permanent free tier is preferable because the value of NextSeason may not become apparent within a short trial period. A user may add a show and wait weeks or months before NextSeason discovers and reports a meaningful update.

The free tier allows users to experience that value naturally before deciding whether they need the paid version.

## NextSeason Plus

NextSeason Plus removes the watchlist limit.

### Paid Feature

**Unlimited show tracking**

There is one paid feature level rather than separate capacity-based plans.

A single paid entitlement:

- Is easier for users to understand.
- Avoids forcing users to predict how many shows they will want to track.
- Eliminates complicated upgrades and downgrades between capacity levels.
- Keeps purchasing and entitlement behavior simple.
- Fits the overall philosophy of keeping NextSeason focused and uncomplicated.

NextSeason Plus can currently be obtained through either a monthly or an annual auto-renewing subscription.

## Annual Subscription

NextSeason Plus Annual is an auto-renewing annual subscription that provides an unlimited watchlist while the subscription remains active.

Annual billing fits the nature of the service better than monthly billing because NextSeason provides value over long periods. A user may wait many months or more than a year for information about a future season.

The subscription supports the continuing service involved in maintaining NextSeason, including:

- Monitoring and processing television data.
- Maintaining compatibility with third-party APIs and services.
- Maintaining the show's data-mapping infrastructure.
- Keeping the app compatible with future versions of iOS.
- Fixing bugs and maintaining reliability.
- Continuing to deliver season information and notifications.

A subscription does **not** imply that NextSeason must continually add new features. The ongoing value is the continuing tracking service itself.

## Monthly Subscription

NextSeason Plus Monthly is an auto-renewing monthly subscription that provides the same unlimited watchlist while active, with monthly billing flexibility.

Both subscriptions belong to the **NextSeason Plus** subscription group and provide the same level of service. Family Sharing is off.

## Subscription Expiration

If a monthly or annual Plus subscription expires, NextSeason does not remove shows or stop tracking shows already on the user's watchlist.

If the watchlist contains more than the free limit when Plus expires:

- All existing shows remain on the watchlist.
- Existing shows continue to be tracked normally.
- Existing notification functionality continues normally.
- The user cannot add another show while the watchlist remains at or above the free limit.
- The user can regain the ability to add shows by renewing Plus or reducing the watchlist below the free limit.

This avoids unexpectedly taking away functionality or data the user already had while still enforcing the free-tier limit for future additions.

## Existing Beta Users

Users who were already tracking more than three shows when the watchlist limit was introduced are grandfathered into an unlimited watchlist.

Grandfathering is determined once when the StoreKit-aware version of NextSeason first runs. If the existing watchlist exceeds the free limit at that time, unlimited access is retained.

Grandfathering is permanent. Reducing the watchlist later does not revoke it.

This prevents beta testers and existing users from losing functionality they already had before monetization was introduced.

## Optional Developer Support

NextSeason includes an optional **Support NextSeason** section in the About screen.

The tip jar uses consumable StoreKit in-app purchases. Multiple tip amounts are offered using television-themed names.

Tips:

- Do not unlock functionality.
- Are entirely optional.
- Are available to both free and Plus users.
- May be purchased more than once.
- Are not promoted through repeated prompts or interruptions.

Their purpose is simply to give users who appreciate the app another way to help keep NextSeason running for years to come.

## Advertising

NextSeason will **not** use advertising.

Advertising is a poor fit for the app because successful use of NextSeason should require very little time in the app. Users should be able to add shows to their watchlist and rely on NextSeason to work quietly in the background.

Low expected ad impressions do not justify the additional:

- Third-party dependencies.
- Privacy considerations.
- Maintenance burden.
- User-interface clutter.
- Potential degradation of the user experience.

## StoreKit Architecture

NextSeason uses native **StoreKit 2** for purchases and entitlement management.

The purchasing system supports:

- An annual auto-renewing NextSeason Plus subscription.
- A monthly auto-renewing NextSeason Plus subscription.
- Consumable tips.
- Purchase restoration.
- Entitlement refresh at launch and when the app becomes active.
- StoreKit transaction updates.
- Beta-user grandfathering.

Both an active monthly subscription and an active annual subscription provide the same NextSeason Plus entitlement: an unlimited watchlist.

Tips never grant Plus functionality.

The app waits for the initial StoreKit entitlement check before enforcing the watchlist limit so that an existing Plus customer is not temporarily treated as a free user during launch.

### Family Sharing

Family Sharing is disabled for the initial NextSeason Plus products.

This decision can be reconsidered after launch if there is a compelling user or business reason to support it.

## Purchase Experience

Users who reach the free watchlist limit are offered the opportunity to unlock NextSeason Plus.

The Plus purchase screen:

- Explains the three-show free limit and unlimited Plus watchlist.
- Displays pricing supplied by StoreKit rather than hard-coded prices.
- Offers Monthly and Annual, with Annual first and labeled Best Value.
- Provides Restore Purchases.
- Includes the required subscription disclosure.
- Provides links to the Terms of Use and Privacy Policy.

The About screen also displays the user's current watchlist entitlement and provides access to NextSeason Plus and Restore Purchases.

Purchase failures or unavailable StoreKit products are handled without changing the user's existing watchlist or entitlement.

## Review Requests

App Store review requests are implemented separately from monetization but follow the same non-intrusive philosophy.

NextSeason becomes eligible to request a review after it has demonstrated meaningful value by successfully delivering the user's first production show-status notification for the current app version.

The review request is delayed briefly so that it occurs while the user is active rather than interrupting the notification itself.

Eligibility is tracked by app version so that review-request behavior can remain appropriately limited.

The About screen also provides a persistent **Rate NextSeason** option that opens the App Store review page directly.

Review requests are not tied to purchases, subscription status, launch counts, or tip activity.

## Pricing

NextSeason Plus launch prices are **$1.99/month** and **$9.99/year**. Annual is the preferred, better-value option.

| Subscription | App Store Connect product ID | US launch price |
| --- | --- | --- |
| Monthly | `com.trialbyfyre.nextseason.plus.monthly` | $1.99/month |
| Annual | `com.trialbyfyre.nextseason.plus.annual` | $9.99/year |

The app displays StoreKit's localized product prices. The local StoreKit configuration and preview/stub Plus prices match the launch decision; tip prices remain provisional.

Both products have been created in App Store Connect in the **NextSeason Plus** group. Before release, verify their prices, durations, equivalent subscription service level, availability, metadata, review status, and that Family Sharing is off. Local StoreKit configuration does not update App Store Connect.

## Initial Product Structure

| Offering | Watchlist | Payment |
| --- | --- | --- |
| NextSeason Free | Up to 3 shows | Free, no expiration |
| NextSeason Plus Annual | Unlimited | $9.99/year auto-renewing subscription |
| NextSeason Plus Monthly | Unlimited | $1.99/month auto-renewing subscription |
| Support NextSeason | No additional functionality | Optional consumable tips |
| Grandfathered Beta Access | Unlimited | No purchase required |

## Status

**Implemented for pre-release testing.**

The StoreKit 2 purchasing architecture, free-tier limit, monthly and annual Plus options, beta grandfathering, optional tips, purchase restoration, and review-request behavior are implemented.

Before App Store release, production products, pricing, legal links, App Store configuration, and purchase behavior must be finalized and validated in the production App Store environment.

The overall strategy may still evolve in response to beta feedback, App Store requirements, operating costs, or experience after launch.
