# TydomConnection execution plan

## Purpose

`TydomConnection` establishes a WebSocket connection to a Delta Dore Tydom gateway (local or remote), performs HTTP Digest authentication, and provides a simple async send/receive interface for HTTP-over-WebSocket frames.

## Connection flow (high level)

1. Build connection configuration (mode, host, mac, credentials, TLS).  
2. Create a `URLSession` (dependency-injected).  
3. Resolve the gateway password:
   - Use direct password if provided.
   - Otherwise fetch it via the cloud API using injected credentials.
4. Fetch the Digest challenge by sending an HTTPS `GET` to `/mediation/client?...` and reading `WWW-Authenticate`.
5. Build the Digest `Authorization` header (MD5, `qop=auth` only).
6. Open the WebSocket with the `Authorization` header.
7. Start the receive loop and expose incoming payloads via `AsyncStream<Data>`.

## Send / receive behavior

- `send(_:)` and `send(text:)` send raw bytes over the socket.
- For **remote mode**, a `0x02` prefix is added on send and stripped on receive.
- Incoming messages are pushed to `messages()` (`AsyncStream<Data>`).

## Error handling

`ConnectionError` surfaces expected failures:
- Missing credentials/password
- Digest challenge errors (missing / invalid)
- Unsupported digest algorithm or `qop`
- Invalid response
- Not connected

## Dependencies (testable by design)

The connection uses a small injected dependency bag for testability:
- `makeSession(allowInsecureTLS, timeout)`
- `randomBytes(count)`
- `now()`
- `fetchGatewayPassword(credentials, mac, session)`
- `invalidateSession(session)`

Unit tests supply fakes for these functions to validate orchestration and error handling.

## Usage example

```swift
let config = TydomConnection.Configuration(
    mode: .local(host: "192.168.1.50"),
    mac: "AA:BB:CC:DD:EE:FF",
    password: "gateway-password"
)

let connection = TydomConnection(configuration: config)
try await connection.connect()

Task {
    for await data in await connection.messages() {
        // Handle HTTP-over-WS frames.
    }
}

let request = "GET /ping HTTP/1.1\r\n\r\n"
try await connection.send(Data(request.utf8))
```

## Notes

- Local mode defaults to relaxed TLS validation to match the legacy Python client.
- Remote mode uses `mediation.tydom.com` and prefixes frames with `0x02`.
- The `AsyncStream` stays alive across connect/disconnect; adjust later if needed.
