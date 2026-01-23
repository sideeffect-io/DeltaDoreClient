import Foundation

public actor TydomDeviceCacheStore {
    private var devices: [String: TydomDeviceCacheEntry] = [:]

    public init() {}

    public func deviceInfo(for uniqueId: String) async -> TydomDeviceInfo? {
        guard let entry = devices[uniqueId],
              let name = entry.name, name.isEmpty == false,
              let usage = entry.usage, usage.isEmpty == false
        else {
            return nil
        }
        return TydomDeviceInfo(name: name, usage: usage, metadata: entry.metadata)
    }

    public func upsert(_ entry: TydomDeviceCacheEntry) async {
        var current = devices[entry.uniqueId] ?? TydomDeviceCacheEntry(uniqueId: entry.uniqueId)
        if let name = entry.name { current.name = name }
        if let usage = entry.usage { current.usage = usage }
        if let metadata = entry.metadata { current.metadata = metadata }
        devices[entry.uniqueId] = current
    }
}
