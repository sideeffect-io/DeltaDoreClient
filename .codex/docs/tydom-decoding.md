# Tydom Message Decoding

## Overview

The decoding pipeline turns raw HTTP-over-WebSocket frames into typed domain messages. It is designed to keep the decoder stateless while allowing cache hydration via injected closures.

### Key types

- `TydomConnection`: exposes an `AsyncStream<Data>` of raw WebSocket frames.
- `TydomMessageDecoder`: parses frames and emits `TydomMessage` values.
- `TydomMessageDecoderDependencies`: injected closures used by the decoder.
- `TydomDeviceCacheStore`: in-memory cache for device identity/metadata.

### Message flow

1. `TydomConnection.messages()` yields raw `Data` frames.
2. `TydomMessageDecoder` parses frames with `TydomHTTPParser`.
3. Routing based on `Uri-Origin`:
   - `/info` → `.gatewayInfo`
   - `/configs/file` → cache upsert (name/usage) via dependency
   - `/devices/meta` → cache upsert (metadata) via dependency
   - `/devices/data` → `.devices` (requires cache lookup for name/usage)
   - `/devices/.../cdata` → `.devices` for `conso` (requires cache lookup)
   - unknown/unsupported → `.raw`

The decoder remains stateless: it delegates cache reads and writes to injected closures.

## Dependencies and cache

`TydomMessageDecoderDependencies` exposes two closures:

- `deviceInfo(uniqueId)` → `TydomDeviceInfo?`
- `upsertDeviceCacheEntry(entry)`

A concrete implementation is provided to connect a `TydomDeviceCacheStore`:

```swift
let cache = TydomDeviceCacheStore()
let deps = TydomMessageDecoderDependencies.fromDeviceCacheStore(cache)
```

`TydomDeviceCacheStore` is in-memory only. If you need persistence, do it in your app layer and feed decoded cache entries back through `upsertDeviceCacheEntry`.

## Usage

```swift
let cache = TydomDeviceCacheStore()
let dependencies = TydomMessageDecoderDependencies.fromDeviceCacheStore(cache)
let decoder = TydomMessageDecoder(dependencies: dependencies)

let connection = TydomConnection(configuration: config)
try await connection.connect()

for await message in connection.decodedMessages(using: decoder) {
    switch message {
    case .gatewayInfo(let info, _):
        // Handle gateway info
    case .devices(let devices, _):
        // Handle devices
    case .raw(let raw):
        // Handle unsupported/unknown
    }
}
```

## Notes

- Device identity (name/usage) comes from `/configs/file`.
- Device metadata comes from `/devices/meta`.
- Device values come from `/devices/data` and `cdata`.
- If cache entries are missing, device updates may be dropped (decoder returns `.raw`).

