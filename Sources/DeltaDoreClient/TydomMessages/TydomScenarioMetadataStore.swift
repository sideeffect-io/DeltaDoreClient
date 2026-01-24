import Foundation

actor TydomScenarioMetadataStore {
    private var entries: [Int: TydomScenarioMetadata] = [:]

    init() {}

    func upsert(_ metadata: TydomScenarioMetadata) {
        entries[metadata.id] = metadata
    }

    func metadata(for id: Int) -> TydomScenarioMetadata? {
        entries[id]
    }

    func clear(id: Int) {
        entries.removeValue(forKey: id)
    }
}
