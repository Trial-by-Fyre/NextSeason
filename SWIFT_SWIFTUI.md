# Swift and SwiftUI Guidance

These rules apply to Swift/SwiftUI projects targeting iOS, iPadOS, macOS, and
watchOS. Supported platforms, deployment targets, and Swift versions are defined
in the project-specific instructions.

- Work as a **Senior Apple Platform Engineer**, specializing in SwiftUI, SwiftData, and related
  frameworks. Follow Apple's Human Interface Guidelines for each supported
  platform and applicable App Review guidelines.
- Use modern Swift concurrency. Prefer async/await APIs over closure-based variants
  where available and appropriate; use callbacks when an API or framework requires them.
- Use SwiftUI and MVVM, backed by `@Observable` classes for shared data.
- Keep views small and readable. Put business logic in view models or services, not
  directly in views.
- Prefer SwiftUI. Use UIKit or AppKit only when requested or approved.
- Choose APIs available on the project's supported platforms and deployment targets.
  Adapt navigation, input, layout, and accessibility to each supported platform;
  do not assume every platform uses iPhone interaction patterns.
- Include previews when practical. Maintain accessibility when adding or changing UI.
- Before writing Swift, read the relevant Swift skill file(s) first and note
  which were used: `swiftui-pro` (SwiftUI views), `swiftdata-pro` (SwiftData /
  persistence), `swift-concurrency-pro` (async/await, actors), `swift-testing-pro`
  (tests).
  The shared skills directory is `~/.agents/skills/`. Read each skill directly at
  `~/.agents/skills/<skill-name>/SKILL.md`, even if it is absent from the session's
  available-skills list. `~/.claude/skills/` may contain symbolic links to these
  directories; a search that does not follow links can miss installed skills.
- Naming: for data-transfer types (DTOs that mirror API JSON), use the `Data`
  suffix in code, e.g. `ShowData`, `SeasonData`, `SearchResultData`. The term
  "DTO" may still be used in documentation.
- In projects using StoreKit, display product prices using StoreKit's localized
  pricing, not hard-coded price strings.
