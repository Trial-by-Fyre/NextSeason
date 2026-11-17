# Building NextSeason TV with AI

I built NextSeason TV to answer a question I kept having after finishing a television show: is another season coming, and when?

The app lets people find shows, save them to a Watchlist, and receive notifications when their season status changes. It's an iPhone app built with Swift, SwiftUI, and SwiftData. It uses TheTVDB for searching and TVMaze for tracking show information, with a mapping layer to maintain consistent show identities across the two services. StoreKit provides an optional subscription for unlimited tracking.

I started development in June 2026 and released version 1.0 on the App Store in November. The core app took approximately three months to build. Much of the remaining two months went into subscriptions, testing, debugging, and release preparation.

## How I worked with AI

I approached AI-assisted development experimentally, without adopting an elaborate methodology or set of prompts.

My basic workflow was to discuss requirements, design alternatives, and implementation approaches with ChatGPT, use Claude for coding, and return to ChatGPT for independent review. I used Xcode, the simulator, and physical devices to investigate failures and verify behavior.

As the developer and product owner, I remained responsible for the app's behavior, architecture, technical decisions, testing priorities, and release readiness. The AI assistants contributed implementation work, analysis, and reviews, but their recommendations still required evaluation.

This approach worked well overall. It also had limitations. Moving between assistants required manually transferring context, and important decisions often ended up buried in conversations that were difficult to find later.

## What I learned

### AI doesn't always identify what you're overlooking

One of my biggest discoveries was that AI assistants often respond effectively to the question they're asked without consistently identifying important questions that haven't been raised.

A technically correct implementation isn't necessarily the best design, and a successful test doesn't establish that every important scenario has been considered.

I found that asking for a code review generally produced a focused technical assessment. Asking for a deeper review, or a review from a different perspective, sometimes revealed significant problems the first review had missed.

This changed how I think about using AI. It's not enough to evaluate the answers. I also need a process that challenges the assumptions behind the questions.

### Integration matters as much as individual features

We reviewed changes throughout development, but those reviews were usually focused on individual features.

Toward the end of V1, broader reviews exposed interactions among features that earlier reviews hadn't adequately considered. By then, some decisions had already been built upon others, making problems harder to untangle.

I learned that independent feature reviews need to be supplemented by periodic reviews of the application as a whole, particularly when changes involve persistence, navigation, background execution, or subscriptions.

### StoreKit was a lesson in behavioral complexity

StoreKit took considerably longer than I expected.

Implementing a purchase was relatively straightforward compared with handling everything that could happen afterward: pending transactions, expiration, refunds, interrupted connectivity, delayed entitlement updates, and application restarts.

NextSeason also has product-specific rules. When someone loses Plus access, the app must enforce the free-tier limit without deleting their saved shows. That requires distinguishing between preserving data and allowing active tracking.

The experience reinforced the importance of defining states, transitions, recovery behavior, and cross-feature interactions before implementation.

It also made me reconsider reusability. I expect to use StoreKit in future apps, and a reusable purchase-management component would be valuable. But the Watchlist rules belong specifically to NextSeason. Identifying that boundary earlier might have simplified future reuse without introducing premature abstractions.

### Speed and learning aren't always compatible

One of my ongoing concerns is how to remain technically engaged while delegating substantial implementation work to AI.

I want to understand the code I'm responsible for maintaining, but thoroughly studying every AI-generated change would eliminate much of the productivity benefit.

I'm still finding the right balance. My current approach is to focus learning on unfamiliar concepts, architectural decisions, and consequential implementation details rather than trying to understand every line immediately.

AI can accelerate development, but I don't want that acceleration to come at the expense of my engineering skills.

## What I'm changing for V2

The experience prompted a retrospective of both the development process and the information we accumulated.

For V2, I'm introducing a more deliberate, risk-based workflow:

- Consider alternative designs, integration risks, and opportunities for reuse before implementing substantial features.
- Define important behavioral scenarios and failure paths early, especially for high-risk changes.
- Use independent reviews that examine architecture, behavior, and cross-feature interactions—not just code correctness.
- Review the application as a whole at meaningful milestones.
- Use GitHub Issues to preserve working history and decisions, while keeping repository documentation focused on the current implementation.
- Incorporate focused learning into development without making every change an extensive study exercise.

The intention isn't to create a heavyweight process. It's to prevent avoidable rework while keeping the simplicity that made AI-assisted development productive in the first place.

## Looking back

NextSeason went from an idea to a released, subscription-based iOS app in about five months. AI made that possible with a smaller investment of implementation time than I would otherwise have expected, but it didn't eliminate the difficult parts of software engineering.

I still had to determine what the product should do, recognize when a proposed solution was inadequate, investigate unexpected behavior, and decide when the app was ready to ship.

My biggest takeaway is that **AI can make writing software faster, but it doesn't replace engineering judgment. If anything, it makes knowing what to question, verify, and challenge even more important.**
