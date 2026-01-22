# Tydom Commands

This package models HTTP-over-WebSocket frames as a pure value type, `TydomCommand`. It keeps request construction deterministic and testable, while the actual side-effect (sending on the socket) stays inside `TydomConnection`.

## Core idea

- `TydomCommand` is an immutable struct containing a fully rendered HTTP/1.1 request string.
- Factory methods build commands from paths, methods, and optional bodies.
- The transaction id is injected (or generated) for deterministic tests.
- Sending is done by `TydomConnection.send(_:)` which delegates to the existing websocket send.

## Building requests

Use `TydomCommand.request(...)` for generic needs, or the legacy convenience factories that mirror the Python client:

```swift
let command = TydomCommand.ping(transactionId: "1234567890123")
try await connection.send(command)
```

The factory builds the HTTP request like the legacy client:

- Status line: `METHOD /path HTTP/1.1`
- Headers: `Content-Length`, `Content-Type`, `Transac-Id`
- Optional body: placed between `\r\n\r\n` and terminated with `\r\n\r\n`

## Convenience factories

The following methods cover the legacy commands:

- `info`, `localClaim`, `geoloc`, `apiMode`, `refreshAll`, `ping`
- `devicesMeta`, `devicesData`, `devicesCmeta`
- `configsFile`, `areasMeta`, `areasCmeta`, `areasData`
- `momentsFile`, `scenariosFile`, `activateScenario`, `groupsFile`
- `deviceData`, `pollDeviceData`, `updateFirmware`
- `putData`, `putDevicesData`
- `alarmCData`, `ackEventsCData`, `historicCData`

### Alarm commands

`alarmCData(...)` returns `[TydomCommand]` to match the legacy behavior where legacy zone strings can expand to multiple commands. For non-legacy usage it returns a single command in the array.

### Transaction ids

Most read-only commands default to `defaultTransactionId()` (timestamp in ms), while PUT-style legacy commands default to `"0"` to match the original Python implementation. You can override `transactionId` in every factory for deterministic testing.

## Sending commands

Sending stays actor-isolated inside `TydomConnection`:

```swift
let command = TydomCommand.devicesData()
try await connection.send(command)
```

This keeps the command creation pure and the side-effect explicit.
