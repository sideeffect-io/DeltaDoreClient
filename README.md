# DeltaDoreClient

Swift package to connect to Delta Dore Tydom gateways, with automatic local/remote selection and cloud-backed
credential discovery.

## Quick start

```swift
import DeltaDoreClient

let client = DeltaDoreClient.live()
let options = DeltaDoreClient.Options(
    mode: .auto,
    cloudCredentials: .init(email: "user@example.com", password: "secret")
)

let session = try await client.connect(
    options: options,
    selectSiteIndex: { sites in
        // Present UI and return the chosen index.
        return 0
    }
)

let connection = session.connection
```

## Listing sites

```swift
let sites = try await client.listSites(
    cloudCredentials: .init(email: "user@example.com", password: "secret")
)
```

## Reset the stored site selection

```swift
try await client.resetSelectedSite(selectedSiteAccount: "default")
```

## Custom services and hosts

```swift
let client = DeltaDoreClient.live(
    credentialService: "com.example.tydom.gateway",
    selectedSiteService: "com.example.tydom.selected-site",
    remoteHost: "mediation.tydom.com"
)
```
