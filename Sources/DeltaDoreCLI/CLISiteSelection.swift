import Foundation
import DeltaDoreClient

func chooseSiteIndex(
    _ sites: [TydomCloudSitesProvider.Site],
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> Int? {
    await printSites(sites, stdout: stdout)
    await stdout.writeLine("Choose a site index:")
    guard let line = readLine(),
          let selection = Int(line),
          sites.indices.contains(selection) else {
        await stderr.writeLine("Invalid selection.")
        return nil
    }
    return selection
}

func printSites(
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
