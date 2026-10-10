//
//  NextSeasonSchemaV1.swift
//  NextSeason
//

import Foundation
import SwiftData

/// First shipped SwiftData schema (app 1.0).
///
/// The persisted model lives on this type as `TrackedShowEntity` so V1 stays
/// a frozen snapshot when a later `NextSeasonSchemaV2.TrackedShowEntity` is
/// added. Do not edit the nested model in place; add a new schema version.
/// (Pre-release exception: `isPaused` was added in place before public release
/// because beta testers start from a fresh database.)
///
/// SwiftData identifies an entity by `Schema.Entity.name` (see
/// `Schema.entityName(for:)`). There is no entity-level `originalName` —
/// `@Attribute(originalName:)` only maps renamed properties. The nested class
/// therefore keeps the name `TrackedShowEntity` so the persistent identity
/// matches stores written by the unversioned top-level model.
enum NextSeasonSchemaV1: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        [TrackedShowEntity.self]
    }
}
