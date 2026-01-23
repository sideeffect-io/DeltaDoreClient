import Foundation

public extension TydomMessageDecoderDependencies {
    static func fromDeviceCacheStore(_ cache: TydomDeviceCacheStore) -> TydomMessageDecoderDependencies {
        TydomMessageDecoderDependencies(
            deviceInfo: { uniqueId in
                await cache.deviceInfo(for: uniqueId)
            },
            upsertDeviceCacheEntry: { entry in
                await cache.upsert(entry)
            }
        )
    }
}
