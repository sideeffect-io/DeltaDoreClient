import Foundation
import DeltaDoreClient

func parseArguments(_ args: [String]) -> StartupAction {
    var mode: String = "local"
    var host: String?
    var mac: String?
    var password: String?
    var cloudEmail: String?
    var cloudPassword: String?
    var siteIndex: Int?
    var bonjourServices: [String] = []
    var timeout: TimeInterval = 10.0
    var pollInterval: Int = 60
    var pollOnlyActive: Bool = true
    var allowInsecureTLS: Bool?
    var listSites: Bool = false
    var forceRemote: Bool = false
    var dumpSitesResponse: Bool = false
    var resetSite: Bool = false

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            return .help(helpText())
        case "--mode":
            index += 1
            guard index < args.count else { return .failure("Missing value for --mode.") }
            mode = args[index].lowercased()
        case "--host":
            index += 1
            guard index < args.count else { return .failure("Missing value for --host.") }
            host = args[index]
        case "--mac":
            index += 1
            guard index < args.count else { return .failure("Missing value for --mac.") }
            mac = args[index]
        case "--password":
            index += 1
            guard index < args.count else { return .failure("Missing value for --password.") }
            password = args[index]
        case "--cloud-email":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-email.") }
            cloudEmail = args[index]
        case "--cloud-password":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-password.") }
            cloudPassword = args[index]
        case "--site-index":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                return .failure("Invalid value for --site-index.")
            }
            siteIndex = value
        case "--bonjour-service":
            index += 1
            guard index < args.count else { return .failure("Missing value for --bonjour-service.") }
            bonjourServices.append(args[index])
        case "--list-sites":
            listSites = true
        case "--no-local":
            forceRemote = true
        case "--dump-sites-response":
            dumpSitesResponse = true
        case "--reset-site":
            resetSite = true
        case "--timeout":
            index += 1
            guard index < args.count, let value = TimeInterval(args[index]) else {
                return .failure("Invalid value for --timeout.")
            }
            timeout = value
        case "--poll-interval":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                return .failure("Invalid value for --poll-interval.")
            }
            pollInterval = value
        case "--poll-only-active":
            index += 1
            guard index < args.count, let value = parseBool(args[index]) else {
                return .failure("Invalid value for --poll-only-active.")
            }
            pollOnlyActive = value
        case "--allow-insecure-tls":
            index += 1
            guard index < args.count, let value = parseBool(args[index]) else {
                return .failure("Invalid value for --allow-insecure-tls.")
            }
            allowInsecureTLS = value
        default:
            return .failure("Unknown argument: \(arg)")
        }
        index += 1
    }

    let credentials: TydomConnection.CloudCredentials?
    if let cloudEmail, let cloudPassword {
        credentials = TydomConnection.CloudCredentials(email: cloudEmail, password: cloudPassword)
    } else {
        credentials = nil
    }

    switch mode {
    case "local":
        let options = ResolveOptions(
            mode: mode,
            host: host,
            mac: mac,
            password: password,
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            listSites: listSites,
            resetSite: resetSite,
            timeout: timeout,
            pollInterval: pollInterval,
            pollOnlyActive: pollOnlyActive,
            allowInsecureTLS: allowInsecureTLS,
            dumpSitesResponse: dumpSitesResponse,
            bonjourServices: bonjourServices.isEmpty ? ["_tydom._tcp"] : bonjourServices
        )
        return .runResolved(options)
    case "remote":
        let options = ResolveOptions(
            mode: mode,
            host: host,
            mac: mac,
            password: password,
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            listSites: listSites,
            resetSite: resetSite,
            timeout: timeout,
            pollInterval: pollInterval,
            pollOnlyActive: pollOnlyActive,
            allowInsecureTLS: allowInsecureTLS,
            dumpSitesResponse: dumpSitesResponse,
            bonjourServices: bonjourServices.isEmpty ? ["_tydom._tcp"] : bonjourServices
        )
        return .runResolved(options)
    case "auto":
        let defaultBonjour = ["_tydom._tcp"]
        let services = bonjourServices.isEmpty ? defaultBonjour : bonjourServices
        let options = AutoOptions(
            mac: mac,
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            bonjourServices: services,
            timeout: timeout,
            pollInterval: pollInterval,
            pollOnlyActive: pollOnlyActive,
            allowInsecureTLS: allowInsecureTLS,
            remoteHost: host,
            listSites: listSites,
            forceRemote: forceRemote,
            dumpSitesResponse: dumpSitesResponse,
            resetSite: resetSite
        )
        return .runAuto(options)
    default:
        return .failure("Invalid --mode value. Use local, remote, or auto.")
    }
}

func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        return nil
    }
}

func helpText() -> String {
    var lines: [String] = []
    lines.append("DeltaDoreCLI")
    lines.append("")
    lines.append("Usage:")
    lines.append("  DeltaDoreCLI --mode local [--host <host>] [--cloud-email <email> --cloud-password <password>]")
    lines.append("  DeltaDoreCLI --mode remote [--host <host>] --cloud-email <email> --cloud-password <password>")
    lines.append("  DeltaDoreCLI --mode auto --cloud-email <email> --cloud-password <password> [--site-index <n>]")
    lines.append("")
    lines.append("Options:")
    lines.append("  --mode local|remote|auto      Connection mode (default: local)")
    lines.append("  --host <host>                 Gateway IP or host (overrides discovery/remote host)")
    lines.append("  --mac <mac>                   Manual gateway MAC (overrides site selection)")
    lines.append("  --password <password>         Local gateway password (optional if stored)")
    lines.append("  --cloud-email <email>         Cloud account email")
    lines.append("  --cloud-password <password>   Cloud account password")
    lines.append("  --site-index <n>              Site index (skips prompt, updates stored selection)")
    lines.append("  --bonjour-service <type>      Bonjour service type (repeatable)")
    lines.append("  --list-sites                  List available sites and exit (requires cloud login)")
    lines.append("  --reset-site                  Clear stored site selection")
    lines.append("  --no-local                    Force remote even if local is available (auto mode)")
    lines.append("  --dump-sites-response         Print raw site list response and exit")
    lines.append("  --timeout <seconds>           Request timeout (default: 10)")
    lines.append("  --poll-interval <seconds>     Polling interval (default: 60, 0 disables)")
    lines.append("  --poll-only-active <bool>     Poll only when active (default: true)")
    lines.append("  --allow-insecure-tls <bool>   Allow insecure TLS (default: true)")
    lines.append("  --help                        Show this help")
    lines.append("")
    lines.append("Once connected, type `help` to list interactive commands.")
    return lines.joined(separator: "\n")
}
