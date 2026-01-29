import Foundation
import DeltaDoreClient

func resolveGatewayCredentials(
    mac: String?,
    cloudCredentials: TydomConnection.CloudCredentials?,
    siteIndex: Int?,
    listSites: Bool,
    dumpSitesResponse: Bool,
    resetSite: Bool,
    selectedSiteStore: TydomSelectedSiteStore,
    selectedSiteAccount: String,
    store: TydomGatewayCredentialStore,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomGatewayCredentials? {
    guard let selectedSite = await resolveSelectedSite(
        mac: mac,
        cloudCredentials: cloudCredentials,
        siteIndex: siteIndex,
        listSites: listSites,
        dumpSitesResponse: dumpSitesResponse,
        resetSite: resetSite,
        selectedSiteStore: selectedSiteStore,
        selectedSiteAccount: selectedSiteAccount,
        stdout: stdout,
        stderr: stderr
    ) else {
        return nil
    }

    let selectedMac = selectedSite.gatewayMac
    let gatewayId = TydomMac.normalize(selectedMac)
    var credentials: TydomGatewayCredentials?
    do {
        credentials = try await store.load(gatewayId)
    } catch {
        await stderr.writeLine("Failed to load credentials: \(error)")
    }

    if credentials == nil {
        guard let cloudCredentials else {
            await stderr.writeLine("No stored credentials. Provide --cloud-email and --cloud-password to fetch them.")
            return nil
        }
        let fetcher = TydomGatewayCredentialFetcher(dependencies: .live(store: store))
        do {
            credentials = try await fetcher.fetchAndPersist(
                gatewayId: gatewayId,
                gatewayMac: selectedMac,
                cloudCredentials: cloudCredentials
            )
            await stdout.writeLine("Fetched and stored gateway credentials.")
        } catch {
            await stderr.writeLine("Failed to fetch gateway credentials: \(error)")
            return nil
        }
    }

    guard let stored = credentials else {
        await stderr.writeLine("Missing gateway credentials.")
        return nil
    }
    return stored
}

private func resolveSelectedSite(
    mac: String?,
    cloudCredentials: TydomConnection.CloudCredentials?,
    siteIndex: Int?,
    listSites: Bool,
    dumpSitesResponse: Bool,
    resetSite: Bool,
    selectedSiteStore: TydomSelectedSiteStore,
    selectedSiteAccount: String,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomSelectedSite? {
    if resetSite {
        do {
            try await selectedSiteStore.delete(selectedSiteAccount)
        } catch {
            await stderr.writeLine("Failed to reset selected site: \(error)")
        }
    }

    if let mac, listSites == false, siteIndex == nil, dumpSitesResponse == false {
        let manual = TydomSelectedSite(id: "manual", name: "Manual selection", gatewayMac: mac)
        do {
            try await selectedSiteStore.save(selectedSiteAccount, manual)
        } catch {
            await stderr.writeLine("Failed to persist manual site selection: \(error)")
        }
        await stdout.writeLine("Using manual gateway MAC (overrides site selection).")
        return manual
    }

    let shouldBypassCache = listSites || siteIndex != nil || resetSite || dumpSitesResponse
    if shouldBypassCache == false {
        do {
            if let stored = try await selectedSiteStore.load(selectedSiteAccount) {
                await stdout.writeLine("Using stored site: \(stored.name) (gateway: \(stored.gatewayMac))")
                return stored
            }
        } catch {
            await stderr.writeLine("Failed to load stored site: \(error)")
        }
    }

    guard let cloudCredentials else {
        await stderr.writeLine("Missing cloud credentials to list sites.")
        return nil
    }

    let session = URLSession(configuration: .default)
    do {
        if dumpSitesResponse {
            let payload = try await TydomCloudSitesProvider.fetchSitesPayload(
                email: cloudCredentials.email,
                password: cloudCredentials.password,
                session: session
            )
            session.invalidateAndCancel()
            let output = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
            await stdout.writeLine(output)
            return nil
        }
        let sites = try await TydomCloudSitesProvider.fetchSites(
            email: cloudCredentials.email,
            password: cloudCredentials.password,
            session: session
        )
        session.invalidateAndCancel()
        guard sites.isEmpty == false else {
            await stderr.writeLine("No sites returned from cloud.")
            return nil
        }
        if listSites {
            await printSites(sites, stdout: stdout)
            return nil
        }
        let chosenIndex: Int?
        if let providedIndex = siteIndex {
            chosenIndex = providedIndex
        } else {
            chosenIndex = await chooseSiteIndex(sites, stdout: stdout, stderr: stderr)
        }
        guard let chosenIndex else { return nil }
        let selectedResult = selectSite(from: sites, index: chosenIndex)
        switch selectedResult {
        case .success(let selected):
            do {
                try await selectedSiteStore.save(selectedSiteAccount, selected)
            } catch {
                await stderr.writeLine("Failed to persist selected site: \(error)")
            }
            await stdout.writeLine("Selected site: \(selected.name) (gateway: \(selected.gatewayMac))")
            return selected
        case .failure(let error):
            await stderr.writeLine(error.message(siteCount: sites.count))
            return nil
        }
    } catch {
        session.invalidateAndCancel()
        await stderr.writeLine("Failed to fetch sites: \(error)")
        return nil
    }
}

private enum SiteSelectionError: Error, Sendable {
    case invalidIndex(Int)
    case missingGateway(String)

    func message(siteCount: Int) -> String {
        switch self {
        case .invalidIndex(let index):
            return "Invalid site index \(index). Available range: 0...\(max(0, siteCount - 1))."
        case .missingGateway(let name):
            return "Selected site has no gateways: \(name)."
        }
    }
}

private func selectSite(
    from sites: [TydomCloudSitesProvider.Site],
    index: Int
) -> Result<TydomSelectedSite, SiteSelectionError> {
    guard sites.indices.contains(index) else {
        return .failure(.invalidIndex(index))
    }
    let site = sites[index]
    guard let gateway = site.gateways.first else {
        return .failure(.missingGateway(site.name))
    }
    let selected = TydomSelectedSite(id: site.id, name: site.name, gatewayMac: gateway.mac)
    return .success(selected)
}

private func chooseSiteIndex(
    _ sites: [TydomCloudSitesProvider.Site],
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> Int? {
    await printSites(sites, stdout: stdout)
    await stdout.writeLine("Choose a site index:")
    guard let line = readLine(), let selection = Int(line), sites.indices.contains(selection) else {
        await stderr.writeLine("Invalid selection.")
        return nil
    }
    return selection
}

private func printSites(
    _ sites: [TydomCloudSitesProvider.Site],
    stdout: ConsoleWriter
) async {
    var lines: [String] = []
    lines.append("Available sites:")
    for (index, site) in sites.enumerated() {
        let gatewayLabel = site.gateways.map { $0.mac }.joined(separator: ", ")
        let gatewaysText = gatewayLabel.isEmpty ? "no gateways" : gatewayLabel
        lines.append("  [\(index)] \(site.name) - \(gatewaysText)")
    }
    await stdout.writeLine(lines.joined(separator: "\n"))
}
